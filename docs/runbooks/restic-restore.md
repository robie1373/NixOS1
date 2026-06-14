# Restic Restore Runbook — by hand, no AI required

**What this is:** step-by-step instructions to get files back from the NAS backup
of flipper's `/home/robie`, for someone with little background. Three jobs:
**(A)** one file, **(B)** a list of files, **(C)** a full restore after the laptop
is dead (bare metal).

**Where this lives / keep it reachable:** this file is in the `nixos-config` repo on
GitHub (`github:robie1373/NixOS1`, `docs/runbooks/restic-restore.md`), so it's
readable from *any* computer during a disaster — do **not** rely on a copy that
only exists on flipper. Consider also keeping a copy in 1Password (Secure Note) or
printed.

**The backup, in one sentence:** restic encrypts `/home/robie` and stores it on the
NAS over SFTP; to read it back you need two secrets from 1Password.

---

## The facts you'll plug in

| Thing | Value |
|---|---|
| Backup location (repo) | `sftp:svc_backup@192.168.20.12:/mnt/tank/backups/laptops/linux/flipper` |
| NAS address | `192.168.20.12` (be on the home LAN that can reach it, or on the Tailscale network) |
| SFTP user | `svc_backup` |
| Repo password | 1Password → vault **devops** → item **`restic-repo-password-flipper`** → field **password** |
| SSH key to the NAS | 1Password → vault **devops** → item **`restic-backup-flipper`** → field **password** ⚠️ (it's a *Login* item; the private key is in the **password** field, not an SSH-key field) |

You will run everything from a terminal on a working computer (a second machine, or
the repaired/reinstalled flipper).

---

## Step 1 — Get the tools

You need `restic` and `ssh`.

- **If the machine has Nix** (any NixOS box, or Nix installed):
  ```
  nix shell nixpkgs#restic nixpkgs#openssh
  ```
  (gives you `restic` and `ssh` for this terminal — nothing is installed permanently.)

- **No Nix?** Download a single restic binary from
  `https://github.com/restic/restic/releases` (pick your OS), unzip it, and use
  `./restic` in place of `restic` below. `ssh` is already on macOS/Linux.

Check it works: `restic version` → should print a version (tested with 0.18.1).

---

## Step 2 — Get the two secrets out of 1Password

You need two small files. **Two ways — pick whichever is easier:**

**Way 1 — copy/paste from the 1Password app (no extra tools):**
1. Open 1Password, vault **devops**.
2. Open **`restic-repo-password-flipper`**, reveal the **password**, paste it into a
   file named `repo-pass.txt` (just the password, nothing else).
3. Open **`restic-backup-flipper`**, reveal the **password** field (this is the SSH
   *private key* — several lines starting with `-----BEGIN OPENSSH PRIVATE KEY-----`),
   paste **all of it** into a file named `nas-key`. Make sure there's a newline at
   the end.

**Way 2 — 1Password CLI (`op`):**
```
op signin
op read "op://devops/restic-repo-password-flipper/password" > repo-pass.txt
op read "op://devops/restic-backup-flipper/password"        > nas-key
```

Then lock down the key file (required, or ssh refuses to use it):
```
chmod 600 nas-key
```
Quick sanity check that the key is valid:
```
ssh-keygen -y -f nas-key
```
→ should print a line starting `ssh-ed25519 …`. If it errors, the paste is
incomplete (missing the BEGIN/END lines or the trailing newline).

---

## Step 3 — Set up the connection (do this once per terminal)

Make a tiny helper script that connects to the NAS with your key:
```
cat > nas-ssh.sh <<'EOF'
#!/usr/bin/env bash
exec ssh -s -i "$PWD/nas-key" -o BatchMode=yes -o StrictHostKeyChecking=accept-new svc_backup@192.168.20.12 sftp
EOF
chmod +x nas-ssh.sh
```

Tell restic where the backup is and how to unlock it:
```
export RESTIC_REPOSITORY="sftp:svc_backup@192.168.20.12:/mnt/tank/backups/laptops/linux/flipper"
export RESTIC_PASSWORD_FILE="$PWD/repo-pass.txt"
```

**Prove you're in** — list the backups:
```
restic -o sftp.command="$PWD/nas-ssh.sh" snapshots
```
You should see a table of snapshots with dates. **If you see that, recovery works** —
the hard part is done. (If not, see Troubleshooting.)

> In every command below, keep the `-o sftp.command="$PWD/nas-ssh.sh"` part — that's
> what makes the NAS connection work. "latest" means the most recent snapshot; you
> can swap in a snapshot ID from the `snapshots` list to restore an older one.

---

## A — Restore ONE file

```
restic -o sftp.command="$PWD/nas-ssh.sh" restore latest \
  --include /home/robie/path/to/the-file \
  --target ./restored
```
The file appears at `./restored/home/robie/path/to/the-file`.

Don't know the exact path? Search the backup first:
```
restic -o sftp.command="$PWD/nas-ssh.sh" ls latest | grep -i part-of-the-name
```

---

## B — Restore a LIST of files

Either repeat `--include` for each file:
```
restic -o sftp.command="$PWD/nas-ssh.sh" restore latest \
  --include /home/robie/fileA \
  --include /home/robie/dir/fileB \
  --include /home/robie/notes \
  --target ./restored
```

…or put one path per line in a file and point restic at it:
```
printf '%s\n' /home/robie/fileA /home/robie/dir/fileB > files.txt
restic -o sftp.command="$PWD/nas-ssh.sh" restore latest \
  --include-file files.txt --target ./restored
```
Everything lands under `./restored/…` mirroring the original paths. A whole folder
works too — `--include /home/robie/Documents` restores the entire folder.

---

## C — FULL restore (bare metal: the laptop died)

Two parts. The backup only covers **your data** (`/home/robie`), not the operating
system.

**Part 1 — get an operating system back.** Install NixOS on the new/repaired machine
from the config repo (`github:robie1373/NixOS1`). That rebuilds the *system*
(packages, services, settings) but starts with an empty home directory. (This is the
normal NixOS install; out of scope for this backup runbook.)

**Part 2 — restore your data from the backup.** Do Steps 1–3 above on the new
machine, then restore everything:

```
# Restore the whole home directory into a staging folder first (safe):
restic -o sftp.command="$PWD/nas-ssh.sh" restore latest --target ./restored
```
This writes everything under `./restored/home/robie/…`. Inspect it, then move it into
place:
```
# As root, so file ownership is preserved:
sudo cp -a ./restored/home/robie/. /home/robie/
sudo chown -R robie:users /home/robie       # only if ownership looks wrong
```
> Restoring directly to `/` (`--target /`) also works and preserves ownership if you
> run restic as **root**, but the staging-folder approach is safer for a first-timer —
> you get to look before overwriting anything.

When it's done, log in as robie; your files, configs, and data are back.

---

## Verify it worked

- The restored files exist under `./restored/…` and open normally.
- Spot-check a known file's contents.
- For a full restore, log in and confirm your documents/settings are present.

## Clean up (important — these are secrets)

```
shred -u nas-key repo-pass.txt 2>/dev/null || rm -f nas-key repo-pass.txt
rm -f nas-ssh.sh files.txt
```

---

## Troubleshooting

| Symptom | Meaning / fix |
|---|---|
| `Resolving password failed: permission denied …/run/agenix/…` | You ran the system's `restic-nas` wrapper, which only works as root on flipper. Use the commands in this runbook (1Password key + `-o sftp.command=…`) instead. |
| `Load key "nas-key": invalid format` / ssh-keygen errors | The key file is incomplete. Re-copy the **entire** `password` field of `restic-backup-flipper`, including the `-----BEGIN/END … -----` lines, and ensure a trailing newline. `chmod 600 nas-key`. |
| `Fatal: wrong password or no key found` | `repo-pass.txt` is wrong/has extra characters. Re-copy the `password` of `restic-repo-password-flipper` (no trailing spaces/newlines added). |
| Hangs / `connection refused` / timeout | You can't reach the NAS at `192.168.20.12`. Get on the home LAN that routes to it, or join the Tailscale network. Confirm with `ping 192.168.20.12`. |
| `repository is already locked` | A previous run was interrupted. `restic -o sftp.command="$PWD/nas-ssh.sh" unlock`, then retry. |
| Restored files owned by wrong user | Run the copy/restore as **root** (`sudo`), or fix afterward: `sudo chown -R robie:users /home/robie`. |

---

## Notes for future maintainers

- Secrets have **two homes**: agenix (`/run/agenix/…`, root-only, used by the
  automated backup + monitor on a *living* flipper) and 1Password (used by this
  by-hand recovery). In a bare-metal event the agenix copies are gone with the disk —
  **1Password is the recovery path**, which is why this runbook uses it.
- Realness ladder if you want more assurance than "files came back": `restic
  snapshots` (exists) → restore a file (this runbook) → `restic check` (repo
  integrity) → `restic check --read-data` (re-reads every byte; slow).
- Companion notes (agent/automation side, on flipper): `~/ledger2/restic.md`.
