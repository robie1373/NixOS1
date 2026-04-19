# Restic Backup Runbook

Restic backups for the NixOS fleet. SFTP transport to TrueNAS, per-host SSH
keypairs, per-host repo encryption passwords. All credentials are age-encrypted
in the repo and stored in 1Password.

---

## Architecture

| Layer | Detail |
|---|---|
| Tool | restic |
| Transport | SFTP via `sftp.command` wrapper (no shell splitting issues) |
| NAS | `192.168.20.12`, user `svc_backup` |
| SSH auth | Per-host ed25519 keypair, private key in `secrets/restic-backup-<host>.age` |
| Repo encryption | Per-host password in `secrets/restic-repo-password-<host>.age` |
| Secret storage | agenix (age-encrypted, decrypted at boot to `/run/agenix/`) |
| 1Password | devops vault: `restic-backup-<host>` and `restic-repo-password-<host>` |
| Schedule | Daily 03:00 ±1h, persistent (catches missed runs after downtime) |
| Retention | 7 daily, 4 weekly, 12 monthly |
| NixOS module | `modules/_features/restic.nix` |
| NixOS service | `restic-backups-nas.service` / `restic-backups-nas.timer` |
| CLI wrapper | `restic-nas` (credentials pre-wired, available after rebuild) |

---

## Host Configuration

| Host | Backup Paths | Extra Excludes | NAS Path |
|---|---|---|---|
| flipper | `/home/robie` | `~/tmp-nas` | `tank/backups/laptops/linux/flipper` |
| fivenix | `/home/robie` | `.ollama`, whisper/huggingface caches, `Steam/steamapps` | `tank/backups/laptops/linux/fivenix` |
| ntfy | `/var/lib/ntfy-sh` | — | `tank/backups/services/ntfy` |
| omada | `/var/lib/omada-controller/data` | — | `tank/backups/services/omada` |
| langlab | `/var/lib/langlab` | — | `tank/backups/services/langlab` |

Common excludes (applied to all hosts in the module):
`**/.cache`, `**/.Trash`, `**/node_modules`, `**/__pycache__`, `**/*.pyc`,
`**/*.swp`, `**/.git/objects`, `**/lost+found`

---

## Day-to-Day Operations

```bash
# Check timer status
systemctl status restic-backups-nas.timer

# Check last run
sudo systemctl status restic-backups-nas.service

# View logs
sudo journalctl -u restic-backups-nas.service

# Trigger a manual run
sudo systemctl start restic-backups-nas.service

# List snapshots
sudo restic-nas snapshots

# Show snapshot contents
sudo restic-nas ls latest

# Check repo integrity
sudo restic-nas check
```

---

## Restore Procedure (host is up)

```bash
# Restore a single file to /tmp/restore
sudo restic-nas restore latest --target /tmp/restore --include /path/to/file

# Restore to original location (careful — overwrites!)
sudo restic-nas restore latest --target /

# Restore from a specific snapshot
sudo restic-nas snapshots          # find snapshot ID
sudo restic-nas restore abc1234 --target /tmp/restore
```

## Restore Procedure (host is unavailable / bare-metal recovery)

Retrieve credentials from 1Password:

```bash
# SSH private key
op read "op://devops/restic-backup-<host>/password" > /tmp/restic-key
chmod 600 /tmp/restic-key

# Repo password
RESTIC_PASSWORD=$(op read "op://devops/restic-repo-password-<host>/password")
```

Run restic directly, wiring the SSH key via `sftp.args`:

```bash
restic \
  -r sftp:svc_backup@192.168.20.12:/mnt/tank/backups/<nas-path> \
  -p <(echo "$RESTIC_PASSWORD") \
  -o sftp.args="-i /tmp/restic-key -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
  snapshots
```

Replace `snapshots` with `restore <id> --target /path/to/restore` as needed.

**Omada note:** Stop the omada-controller service before restoring MongoDB data.
Restore to `/var/lib/omada-controller/data`, then restart.

---

## Adding a New Host

### 1. Generate SSH keypair

```bash
ssh-keygen -t ed25519 -f /tmp/restic-backup-<host> -N "" -C "restic-backup-<host>"
```

### 2. Store private key in 1Password

```bash
op item create \
  --category Login \
  --title "restic-backup-<host>" \
  --vault devops \
  "password=$(cat /tmp/restic-backup-<host>)"
```

### 3. Generate and store repo password

```bash
REPO_PASS=$(openssl rand -base64 32)
op item create \
  --category Login \
  --title "restic-repo-password-<host>" \
  --vault devops \
  "password=$REPO_PASS"
```

### 4. Get the host's SSH host public key

For servers already provisioned:
```bash
ssh-keyscan -t ed25519 <host-ip> 2>/dev/null | awk '{print $2, $3}'
```

Commit it to the repo:
```bash
# paste the key
echo "ssh-ed25519 AAAA..." > hosts/<host>/ssh_host_ed25519_key.pub
git add hosts/<host>/ssh_host_ed25519_key.pub
```

### 5. Add host to `secrets/secrets.nix`

```nix
<host> = "ssh-ed25519 AAAA...";  # host SSH public key
# add to tailscaleServers list if applicable
"restic-backup-<host>.age".publicKeys       = [ <host> ];
"restic-repo-password-<host>.age".publicKeys = [ <host> ];
```

### 6. Encrypt secrets

Use `nix run nixpkgs#age` directly (bypasses agenix's EDITOR mechanism):

```bash
HOST_PUBKEY=$(cat hosts/<host>/ssh_host_ed25519_key.pub | awk '{print $1, $2}')

# Encrypt SSH private key
printf '%s' "$(op read 'op://devops/restic-backup-<host>/password')" \
  | nix run nixpkgs#age -- --encrypt -r "$HOST_PUBKEY" \
      -o secrets/restic-backup-<host>.age -

# Encrypt repo password
printf '%s' "$(op read 'op://devops/restic-repo-password-<host>/password')" \
  | nix run nixpkgs#age -- --encrypt -r "$HOST_PUBKEY" \
      -o secrets/restic-repo-password-<host>.age -

# Clean up
rm /tmp/restic-backup-<host> /tmp/restic-backup-<host>.pub
```

### 7. Add SSH public key to NAS

In TrueNAS UI → Credentials → Users → `svc_backup` → Edit → SSH Public Keys,
add the backup public key:

```bash
cat /tmp/restic-backup-<host>.pub
# or: op read "op://devops/restic-backup-<host>/username"  # if stored there
```

Public key format: `ssh-ed25519 AAAA... restic-backup-<host>`

### 8. Enable restic in host configuration

Desktop host (`hosts/<host>/configuration.nix`):
```nix
imports = [
  # ...
  ../../modules/_features/restic.nix
];

mySystem.restic = {
  enable  = true;
  nasPath = "tank/backups/laptops/linux/<host>";
  paths   = [ "/home/robie" ];
  exclude = [ "/home/robie/some-large-dir" ];  # optional
};
```

Server host — restic.nix is already imported via `../../modules/_features/restic.nix`
in `hosts/<host>/configuration.nix`. Just add the `mySystem.restic` block.

### 9. Ensure `self` in specialArgs (server hosts only)

Server host `modules/hosts/<host>/default.nix` must pass `self`:

```nix
{ inputs, self, ... }:
{
  flake.nixosConfigurations.<host> = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [ ... ];
  };
}
```

Desktop hosts get `self` via the mkHost helper in `parts/nixos.nix`.

### 10. Build and deploy

```bash
# On the host itself
rebuild

# Or remote for server hosts
nixos-rebuild switch --flake .#<host> --target-host root@<host-ip>
```

### 11. Verify

```bash
sudo systemctl status restic-backups-nas.service
sudo journalctl -u restic-backups-nas.service
sudo restic-nas snapshots   # after first run completes
```

---

## Re-keying Existing Secrets

After adding a new host to `secrets/secrets.nix` (e.g. adding it to `tailscaleServers`),
re-encrypt all secrets for the new recipient:

```bash
nix run github:ryantm/agenix -- -r
```

---

## Secrets at Runtime

After boot, agenix decrypts to:
- `/run/agenix/restic-backup-<hostname>` — SSH private key (mode 0400, owner root)
- `/run/agenix/restic-repo-password-<hostname>` — repo password (mode 0400, owner root)

The `sftp.command` wrapper in `restic.nix` references the SSH key path directly.
The NixOS restic module reads `passwordFile` for the repo password.

---

## Troubleshooting

**`Could not resolve hostname sftp`**
The `sftp.command` script has a syntax error. SSH's `-s` flag takes no argument;
`sftp` must appear after the destination: `ssh -s -i key user@host sftp`.

**`unknown command /run/agenix/restic-backup-...`**
`sftp.args` was used instead of `sftp.command`. The NixOS module does not quote
extraOptions values, so a key path with no spaces was parsed as a restic subcommand.
Fix: use `sftp.command` with a wrapper script (no shell splitting on store paths).

**`Permission denied (publickey)`**
The backup public key is not in `svc_backup`'s authorized_keys on the NAS, or
the private key path in the wrapper is wrong. Check `/run/agenix/` for the key file.

**`Fatal: unable to open config file`**
Repo not initialised. Set `initialize = true` in the restic module config (already
set in `restic.nix`). Run `sudo restic-nas init` manually if needed.

**Service fails with "trusted users" error during deployment**
If deploying via `nix copy` from another host, the target must have:
```nix
nix.settings.trusted-users = [ "root" "robie" ];
```
This is set in `modules/_features/common.nix`. Bootstrap by rsyncing the config
and building locally on the target host.
