# NAS / SMB Shares

Two ways to access SMB/CIFS shares on this setup:

- **GVfs** — virtual mount managed by the GNOME virtual filesystem daemon.
  No root, no `/etc/fstab`. Best for quick interactive browsing.
- **`nas-mount` script** — a real kernel CIFS mount at `/mnt/nas`.
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

Before first use, create a Login item in 1Password for the NAS credentials:

```bash
op item create \
  --category login \
  --title "NAS" \
  --vault "Private" \
  username="your-nas-user" \
  password="your-nas-password"
```

The scripts read from `op://Private/NAS/username` and
`op://Private/NAS/password`. If your vault or item name differs, edit
the `OP_VAULT` and `OP_ITEM` variables at the top of
`modules/home/nas.nix` and rebuild.

---

## Mounting

```bash
# Mount the default share (configured in nas-mount)
nas-mount

# Mount a specific share at the default mount point
nas-mount //nas-hostname/share-name

# Mount a specific share at a custom path
nas-mount //nas-hostname/share-name /mnt/myshare
```

On first run (or after the 1Password session expires), `op` will prompt
for biometric or master-password authentication. After that it reuses the
session silently until it times out.

**What happens under the hood:**

1. `op read` fetches username and password from the vault
2. Credentials are written to a tmpfs file under `/run/user/$(id -u)/`
   (never touches a real disk)
3. A `trap` ensures the file is deleted even if `mount.cifs` fails
4. `sudo mount.cifs` is called with the tmpfs credentials file
5. The temp file is removed

The sudoers rule in `modules/system/nas.nix` allows `mount.cifs` and
`umount /mnt/nas` without a password prompt, using the exact Nix store
paths so the permission is always in sync with the installed binaries.

---

## Unmounting

```bash
# Unmount the default /mnt/nas
nas-umount

# Unmount a custom path
nas-umount /mnt/myshare
```

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

## Troubleshooting

```bash
# Check if the share is mounted
mount | grep cifs

# Check kernel CIFS messages
dmesg | grep -i cifs

# Test 1Password access directly
op read "op://Private/NAS/username"
op read "op://Private/NAS/password"

# Manual mount for debugging
sudo mount.cifs //nas-hostname/share /mnt/nas \
  -o username=user,password=pass,uid=$(id -u),gid=$(id -g),vers=3.0
```

---

## Security Notes

- Credentials are fetched at runtime from 1Password and written to a
  tmpfs file (`/run/user/UID/`). They are never stored on disk between
  mounts.
- The sudoers rules reference exact Nix store paths for `mount.cifs` and
  `umount`, so they stay in sync with the installed package versions
  across rebuilds.
- If you use Tailscale, you can access NAS shares by Tailscale hostname
  even when not on the local network — CIFS works over Tailscale as long
  as latency is reasonable.
- For a NAS with self-signed certificates (some Synology/QNAP configs),
  you may need to add `seal` or `noblocksend` to the mount options
  depending on your SMB version negotiation.
