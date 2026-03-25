# Guide 05: Troubleshooting

Common failure modes, how to diagnose them, and how to fix them.

---

## General Approach

**Always build before switching:**
```bash
nixos-rebuild build --flake .#nixos1
```
A build failure is a Nix error — a message in the terminal.  A runtime failure is
something that went wrong after the switch.  Keep them separate in your mental model.

**Check Hyprland's own log first:**
```bash
cat /tmp/hypr/$(ls /tmp/hypr)/hyprland.log
# or, to watch it live while Hyprland is running:
tail -f /tmp/hypr/$(ls /tmp/hypr)/hyprland.log
```

**Check systemd journal for user services:**
```bash
journalctl --user -b          # all user-service logs since last boot
journalctl --user -u waybar   # specific service
journalctl --user -xe          # recent errors with context
```

---

## Build-Time Errors

### `error: attribute 'nerd-fonts' missing`

The new `nerd-fonts.<name>` style requires a recent nixpkgs-unstable.  If your flake
lock is older, either run `nix flake update` or use the old syntax:

```nix
# Old syntax (still works on older nixpkgs)
(pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
```

---

### `error: The option 'services.displayManager.sddm.enable' conflicts`

You have both `services.greetd.enable = true` (from Hyprland module) and
`services.displayManager.sddm.enable = true` (from KDE module) active at the same time.

Fix: disable SDDM in `modules/system/desktop-kde.nix` by removing or setting
`services.displayManager.sddm.enable = false;`, or set `mySystem.desktopKde.enable = false`
in `configuration.nix`.

---

### `error: option 'catppuccin-gtk.override' ...`

The `catppuccin-gtk` package override syntax can change between nixpkgs versions.
Check what overrides are available:
```bash
nix repl
nix-repl> :l <nixpkgs>
nix-repl> pkgs.catppuccin-gtk.override
```

If the override fails, you can use the package without customization as a fallback:
```nix
gtk.theme = {
  name    = "Catppuccin-Macchiato-Standard-Mauve-Dark";
  package = pkgs.catppuccin-gtk;
};
```
The name must still match what the package installs — check with
`ls $(nix build nixpkgs#catppuccin-gtk --print-out-paths)/share/themes/`.

---

## Runtime: greetd / Login

### Black screen after greetd login

You see the tuigreet prompt, enter your credentials, and get a black screen.

**Cause 1 — Hyprland can't find a display:**
In a VM, the QEMU display must be active.  Check that you're booting with a display
output (not headless).

**Cause 2 — Hyprland crashes immediately:**
Check the Hyprland log before it clears:
```bash
# From a TTY (Ctrl+Alt+F2)
journalctl -b | grep -i hypr
```

**Cause 3 — Wrong session command:**
The greetd config uses `--cmd Hyprland`.  Verify `Hyprland` is in PATH:
```bash
which Hyprland      # should return /run/current-system/sw/bin/Hyprland
```

---

### tuigreet login loop (enters password, returns to login prompt)

**Cause — PAM configuration issue or wrong username/password.**

Check PAM errors:
```bash
journalctl -b | grep -i pam
journalctl -b | grep -i greetd
```

Make sure the `greeter` user exists (it should be created automatically by the greetd
NixOS module):
```bash
id greeter
```

---

### Can't reach greetd — stuck at a black TTY

Switch to another TTY: `Ctrl+Alt+F2`.  Login as root or your user.  Check greetd:
```bash
systemctl status greetd
journalctl -u greetd -b
```

Emergency fallback — start Hyprland manually from TTY:
```bash
Hyprland
```

---

## Runtime: Hyprland

### Monitor not detected / wrong resolution

Hyprland starts but shows a different resolution than configured.

Check what Hyprland sees:
```bash
hyprctl monitors
```

The `name` field must exactly match your `monitor =` line.  In a VM it's always
`Virtual-1`.  On physical hardware it will be `DP-1`, `HDMI-A-1`, `eDP-1`, etc.

To auto-detect any monitor without specifying a name:
```nix
monitor = ",preferred,auto,1";
# format: name, resolution, position, scale
# empty name = match any monitor
# "preferred" = use monitor's preferred resolution
# "auto" = auto-position
```

---

### Waybar doesn't appear

Start it manually to see the error:
```bash
pkill waybar; waybar 2>&1 | head -50
```

Common causes:
- JSON syntax error in the `settings` (missing comma, wrong type) — the Nix→JSON
  conversion will usually catch this at build time, but some errors slip through
- A referenced module name doesn't exist (e.g., `"battery"` on a desktop with no battery)
- Font not found — Waybar falls back silently but may crash on icon glyphs

---

### Wallpaper not loading (desktop is black or grey)

Check whether swaybg is running:
```bash
pgrep -a swaybg
```

Restart it manually to see any error output:
```bash
pkill swaybg; swaybg -i /home/robie/nixos-config/media/redwoods.png -m fill &
```

Or use the `wallpaper` Fish function:
```fish
wallpaper /home/robie/nixos-config/media/redwoods.png
```

Verify the wallpaper path is correct and readable:
```bash
ls -la /home/robie/nixos-config/media/redwoods.png
```

The path in the Nix config must be an absolute path on the live system.  If you moved
the nixos-config repo, update the path in the `exec-once` swaybg line and rebuild.

---

### Rofi doesn't open or looks plain (no theme)

Start rofi manually:
```bash
rofi -show drun
```

If it opens but uses the default theme, the `.rasi` file isn't being found.  Check:
```bash
ls ~/.config/rofi/themes/
# Should show catppuccin-macchiato.rasi
```

If the file is missing, Home Manager didn't apply.  Rebuild home-manager:
```bash
home-manager switch --flake /home/robie/nixos-config#robie@nixos1
# or
sudo nixos-rebuild switch --flake .#nixos1
```

---

### Hyprlock doesn't unlock (password rejected)

The most common cause: `security.pam.services.hyprlock = {}` is missing from the
system module.

Verify it's in the built system:
```bash
cat /etc/pam.d/hyprlock
```

If that file doesn't exist, the PAM rule wasn't applied.  Add the line to
`modules/system/desktop-hyprland.nix` and rebuild.

---

### Notifications don't appear

Check dunst is running:
```bash
pgrep -a dunst
```

Test it manually:
```bash
notify-send "Test" "Hello from dunst"
```

If dunst isn't running:
```bash
dunst &
notify-send "Test" "Hello"
```

If another notification daemon is running (e.g., from KDE), it will conflict with
dunst.  Check:
```bash
ps aux | grep -E 'dunst|knotify|notification'
```

Kill the competing daemon and start dunst.

---

### GTK apps look unstyled (default grey theme)

GTK4 apps in particular often ignore the `gtk.theme` setting.  Fixes in order of
preference:

1. **Add env var** to `home.sessionVariables` in the home module:
   ```nix
   home.sessionVariables.GTK_THEME = "Catppuccin-Macchiato-Standard-Mauve-Dark";
   ```

2. **Use nwg-look** to force-apply GTK settings interactively:
   ```bash
   nwg-look
   ```
   Hit Apply.  This writes to `~/.config/gtk-3.0/` and `~/.config/gtk-4.0/` directly.

3. **Verify the theme is installed:**
   ```bash
   ls ~/.nix-profile/share/themes/ | grep Catppuccin
   ```

---

### Qt apps look unstyled

`qt.platformTheme.name = "gtk"` requires `QT_QPA_PLATFORMTHEME=gtk` to be set.
Home Manager sets this, but check:
```bash
echo $QT_QPA_PLATFORMTHEME
```

If it's empty, the session variables weren't sourced.  This can happen if you start
Hyprland from a TTY without going through greetd (which sources the NixOS session
environment).  Always log in via greetd for a properly-configured environment.

---

### XWayland apps are blurry or have wrong cursor

Some older apps don't support native Wayland and run via XWayland (the X11
compatibility layer).  They're slightly blurry on HiDPI and may show the wrong cursor.

You can't fully fix the blur, but you can fix the cursor:
```nix
home.sessionVariables = {
  XCURSOR_THEME = "Catppuccin-Macchiato-Dark-Cursors";
  XCURSOR_SIZE  = "24";
};
```

To see which apps are using XWayland:
```bash
hyprctl clients | grep -A5 "xwayland: 1"
```

---

### Screen share / OBS / Discord video capture broken

This is almost always a portal issue.

Check portals are running:
```bash
systemctl --user status xdg-desktop-portal
systemctl --user status xdg-desktop-portal-hyprland
systemctl --user status xdg-desktop-portal-gtk
```

Restart them:
```bash
systemctl --user restart xdg-desktop-portal
systemctl --user restart xdg-desktop-portal-hyprland
```

OBS also requires the `pipewire` system service and `obs-studio` to be built with
the `wlrobs` or `pipewire` plugin.  Verify PipeWire is running (it should be, since
audio.nix enables it):
```bash
systemctl --user status pipewire
```

---

## Useful Diagnostic Commands Cheatsheet

```bash
# Hyprland state
hyprctl monitors          # display configuration
hyprctl clients           # open windows
hyprctl workspaces        # workspace list
hyprctl version           # Hyprland version

# Log files
cat /tmp/hypr/$(ls /tmp/hypr)/hyprland.log
journalctl --user -b -u waybar
journalctl --user -b -u dunst
journalctl --user -b -u hypridle
journalctl --user -b -u xdg-desktop-portal

# Processes
pgrep -a waybar
pgrep -a swaybg
systemctl --user status dunst
systemctl --user status hypridle

# Theme verification
ls ~/.config/gtk-3.0/settings.ini
ls ~/.config/gtk-4.0/settings.ini
echo $GTK_THEME
echo $QT_QPA_PLATFORMTHEME
fc-list | grep JetBrains

# Clipboard
wl-paste            # print clipboard contents
echo "test" | wl-copy && wl-paste  # verify wl-clipboard works
```

---

## Rolling Back

If the system is in a bad state after switching:

**From within a working session:**
```bash
sudo nixos-rollback
```

**From the boot menu:**
At the boot menu, select the previous NixOS generation.  All generations are kept
until you run `nix-collect-garbage`.

**Reverting flake.lock after a bad `nix flake update`:**
```bash
git checkout flake.lock
sudo nixos-rebuild switch --flake .#nixos1
```
