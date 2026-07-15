# NAS / SMB Shares

Two ways to access SMB/CIFS shares on this setup:

- **GVfs** — virtual mount managed by the GNOME virtual filesystem daemon.
  No root, no `/etc/fstab`. Best for quick interactive browsing.
- **`nas-mount` script** — a real kernel CIFS mount at `/mnt/nas/<share>`.
  Credentials are fetched at runtime from 1Password — nothing plaintext on
  disk. Best for stable paths that scripts and apps (yazi's `gn`, mpd's
  music directory) can rely on.

Both are available simultaneously.

---

## Module Setup

Two modules wire this up. Both are enabled on flipper:

| Module                    | Key                    | What it does                                      |
|---------------------------|------------------------|---------------------------------------------------|
| `modules/system/nas.nix`  | `mySystem.nas.enable`  | Creates `/mnt/nas`, installs cifs-utils, sudoers  |
| `modules/home/nas.nix`    | `myHome.nas.enable`    | Installs `nas-mount` and `nas-umount` scripts     |

---

## 1Password Setup (one-time)

Before first use, create a Login item in 1Password for the NAS credentials.
The item must be in the **devops** vault (the CLI is restricted to that vault;
Private is unavailable):

```bash
op item create \
  --category login \
  --title "NAS" \
  --vault "devops" \
  username="your-nas-user" \
  password="your-nas-password"
```

The scripts read credentials using `op item get NAS --vault devops --fields ...`.
If your vault or item name differs, edit the `OP_VAULT` and `OP_ITEM` variables
at the top of `modules/home/nas.nix` and rebuild.

---

## Mounting

```bash
# Mount the default share (//nas01/fauxbox → /mnt/nas/fauxbox)
nas-mount

# Mount a different share (mount point derived from share name)
nas-mount //nas01/ad-hoc-backups    # → /mnt/nas/ad-hoc-backups

# Mount a specific share at a custom path
nas-mount //nas01/photos /mnt/photos
```

The mount point is derived automatically from the share name when only one
argument is given. The directory is created if it doesn't exist.

On first run (or after the 1Password session expires), `op` will prompt
for authentication. After that it reuses the session silently until it
times out.

**What happens under the hood:**

1. `op item get` fetches username and password from the devops vault
   (`--reveal` is used for the password field since `op` conceals it by default)
2. Credentials are written to a tmpfs file under `/run/user/$(id -u)/`
   (never touches a real disk)
3. A `trap` ensures the file is deleted even if `mount.cifs` fails
4. `sudo mount.cifs` is called with the credentials file, `domain=WORKGROUP`,
   and `sec=ntlmssp`
5. The temp file is removed

---

## Unmounting

```bash
# Unmount the default /mnt/nas
nas-umount

# Unmount a custom path
nas-umount /mnt/nas/ad-hoc-backups
```

---

## Key Design Decisions and Gotchas

### Why `op item get` instead of `op read`

`op read "op://vault/item/field"` requires the 1Password desktop app integration
socket to be working. On this Hyprland setup the socket (`/run/user/1000/op-daemon.sock`)
frequently goes stale (see the 1Password troubleshooting section below).

`op item get ITEM --vault VAULT --fields FIELD` works with both the desktop app
integration and standalone CLI sessions (`op signin`), making it more resilient.

### Why `--reveal` on the password field

`op item get` conceals password fields by default (returns `****` even in scripts).
The `--reveal` flag is required to get the actual plaintext. The username field
is not concealed and doesn't need it.

### Why no `_1password-cli` in `runtimeInputs`

`writeShellApplication` prepends `runtimeInputs` to PATH. If `pkgs._1password-cli`
is listed, its `op` binary shadows the system's `/run/wrappers/bin/op` (installed
by `programs._1password.enable`). The wrapper version is the one that can talk to
the 1Password desktop app. Using the wrong binary causes "connecting to desktop
app: connection reset" errors even when the desktop app is healthy.

### Why `mount.cifs` without a Nix store path

The script calls `sudo mount.cifs` rather than `sudo ${pkgs.cifs-utils}/bin/mount.cifs`.
`sudo` has its own restricted PATH and cannot resolve Nix store paths. Since
`cifs-utils` is installed system-wide via `modules/system/nas.nix`, `mount.cifs`
is available at `/run/current-system/sw/bin/mount.cifs`.

### Why `domain=WORKGROUP` and `sec=ntlmssp`

The UGREEN NAS (UGOS) requires these for authentication. Without them, CIFS
returns `STATUS_LOGON_FAILURE` (error 13, permission denied). The domain is
written into the credentials file alongside username and password.

---

## 1Password CLI Troubleshooting

The 1Password desktop app integration on Linux (Hyprland/Wayland) is fragile.
The `op-daemon` process that creates the IPC socket can die without the GUI
app noticing, leaving a stale PID file.

**Symptoms:**
- `op item get` / `op read` fail with "connecting to desktop app: connection reset"
- `op whoami` still works (doesn't need the socket)
- `/run/user/1000/op-daemon.sock` is missing or stale

**Fix:**
```bash
rm -f /run/user/1000/op-daemon.sock /run/user/1000/op-daemon.pid
# Then interact with the 1Password GUI (open it, click something)
# Next op command will prompt: "turn on 1Password app integration? [Y/n]" → Y
op item get NAS --vault devops --fields username
```

**What does NOT help:**
- `systemctl --user restart onepassword-gui` (restarts app, doesn't recreate socket)
- `op signin` alone (creates CLI session but `op read` still tries desktop app first)
- `op account add` (refuses — says CLI is connected with 1Password app)
- Turning off "Integrate with 1Password CLI" in app settings (triggers full
  re-sign-in, may hit "MFA type not supported" error)

---

## GVfs (Interactive / No Config Required)

`services.gvfs.enable = true` is set in `modules/system/common.nix` so
the daemon is running on every host.

```bash
# Mount a share
gio mount smb://nas/music

# Mount with explicit credentials
gio mount smb://user@nas/music

# List currently mounted GVfs locations
gio mount -l

# Unmount
gio mount -u smb://nas/music
```

GVfs mounts appear under:

```
/run/user/1000/gvfs/smb-share:server=nas,share=music/
```

That path is long and not useful for scripts. For anything that needs a
stable path, use `nas-mount` instead.

When `gnome-keyring` is running, GVfs saves credentials in the keyring
and reuses them automatically. Without keyring support, the prompt
reappears every time.

---

## Integrating with the App Stack

### yazi

The `gn` shortcut in `modules/home/yazi.nix` points at `/mnt/nas`.
After `nas-mount`, pressing `gn` in yazi navigates there directly.

To add shortcuts for multiple shares:

```nix
keymap.manager.prepend_keymap = [
  { on = ["g" "h"]; run = "cd ~";                  desc = "Go home"; }
  { on = ["g" "d"]; run = "cd ~/Downloads";          desc = "Go Downloads"; }
  { on = ["g" "c"]; run = "cd ~/.config";            desc = "Go config"; }
  { on = ["g" "n"]; run = "cd /mnt/nas";             desc = "Go NAS root"; }
  { on = ["g" "N" "m"]; run = "cd /mnt/nas/music";  desc = "Go NAS music"; }
  { on = ["g" "N" "p"]; run = "cd /mnt/nas/photos"; desc = "Go NAS photos"; }
];
```

### MPD

To play music from the NAS, point MPD at the mount:

```nix
# In modules/home/mpd.nix
services.mpd.musicDirectory = "/mnt/nas/music";
```

Or symlink:

```bash
ln -s /mnt/nas/music ~/Music
```

After pointing MPD at the share, update the database:

```bash
mpc update
```

### imv / zathura

These open files directly — navigate to `/mnt/nas/...` in yazi and press
`Enter`. Run `nas-mount` first if the share isn't already up.

---

## Checking What's Available on the NAS

Browse available shares without mounting anything:

```bash
# List all shares on a host (requires smbclient from pkgs.samba)
smbclient -L nas-hostname -U username

# Or anonymously (if the NAS allows it)
smbclient -L nas-hostname -N
```

`smbclient` is not installed by default. Add it temporarily:

```bash
nix shell nixpkgs#samba -c smbclient -L nas-hostname -N
```

---

## Security Notes

- Credentials are fetched at runtime from 1Password and written to a
  tmpfs file (`/run/user/UID/`). They are never stored on disk between
  mounts.
- The sudoers rules in `modules/system/nas.nix` allow `mount.cifs` and
  `umount /mnt/nas` without a password prompt.
- If you use Tailscale, you can access NAS shares by Tailscale hostname
  even when not on the local network — CIFS works over Tailscale as long
  as latency is reasonable.
