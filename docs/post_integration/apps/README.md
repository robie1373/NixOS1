# Application Guides

End-user guides for the application stack configured in `modules/home/`.
Each app has its own module with an enable flag — see `hosts/flipper/home.nix`
for what's active on each host.

---

## The Stack

| Role         | App              | Module                     | Config key              |
|--------------|------------------|----------------------------|-------------------------|
| Video        | mpv              | `modules/home/mpv.nix`     | `myHome.mpv.enable`     |
| PDF reader   | zathura          | `modules/home/zathura.nix` | `myHome.zathura.enable` |
| Image viewer | imv              | `modules/home/imv.nix`     | `myHome.imv.enable`     |
| Music        | MPD + ncmpcpp    | `modules/home/mpd.nix`     | `myHome.mpd.enable`     |
| File manager | yazi             | `modules/home/yazi.nix`    | `myHome.yazi.enable`    |

---

## Guides

- **[yazi.md](./yazi.md)** — Full primer + hands-on exercises. Start here if
  you're new to terminal file managers.
- **[mpv.md](./mpv.md)** — Video/audio playback, keyboard reference, uosc UI.
- **[zathura.md](./zathura.md)** — PDF reading, vim keybindings, recolor mode.
- **[imv.md](./imv.md)** — Image viewing, slideshow, keybindings.
- **[mpd-ncmpcpp.md](./mpd-ncmpcpp.md)** — Music daemon setup, ncmpcpp TUI,
  visualiser, `mpc` quick reference.
- **[nas-smb.md](./nas-smb.md)** — `nas-mount`/`nas-umount` scripts backed
  by 1Password (no plaintext credentials), GVfs for interactive browsing,
  integration with yazi/mpd/imv.

---

## Integration Notes

**xdg-open routing** — zathura and imv are registered as default handlers via
`xdg.mimeApps` in their modules. This means yazi's `open` rule (which calls
`xdg-open`) automatically routes PDFs to zathura and images to imv. No manual
wiring needed.

**NAS shares** — yazi has a `gn` goto shortcut pointing at `/mnt/nas`. Run
`nas-mount` to mount (credentials come from 1Password, nothing plaintext on
disk) and all apps can reach the share through the normal file picker or yazi.

**mpv + yt-dlp** — mpv can stream directly from YouTube and other sites.
Pass a URL as the argument or use the `open-url` keybind inside mpv.
