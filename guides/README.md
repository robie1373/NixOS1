# Hyprland Desktop Setup Guide

This guide walks you through building a full Hyprland desktop on NixOS, following the
modular pattern already established in this config.  You write the files; nothing here
is automated.

---

## What You're Building

| Role              | Tool                              |
|-------------------|-----------------------------------|
| Compositor / WM   | Hyprland                          |
| Status bar        | Waybar                            |
| App launcher      | rofi-wayland                      |
| Display manager   | greetd + tuigreet                 |
| Notifications     | Dunst                             |
| Desktop portal    | xdg-desktop-portal-hyprland       |
| Wallpaper         | Hyprpaper                         |
| Screen locker     | Hyprlock                          |
| Idle daemon       | Hypridle                          |
| Terminal          | Kitty                             |
| Shell             | Fish                              |
| GTK theme         | Catppuccin-GTK (Macchiato/Mauve)  |
| Icons             | Papirus-Dark                      |
| Cursor            | Catppuccin Macchiato Dark         |
| Qt theme          | follows GTK via platformTheme     |
| Fonts             | JetBrainsMono Nerd Font           |

---

## Why These Tools?

### Kitty
GPU-accelerated and native Wayland from the start.  It renders fonts with full ligature
support and implements the *kitty graphics protocol* — images displayed inline in the
terminal, used by tools like `ranger`, `yazi`, and `neofetch --kitty`.  It's also fast:
startup is almost instant because it stays resident in memory between windows.

### Fish
Fish gives you auto-suggestions, syntax highlighting, and smart tab-completion **out of
the box** — no plugin manager, no `.bashrc` hacks.  The trade-off is that Fish is **not
POSIX-compatible**.  Shell scripts should still use `#!/usr/bin/env bash`.  Fish is your
*interactive* shell; Bash is still the scripting language.  They coexist fine.

### greetd + tuigreet vs SDDM
SDDM is the display manager used by KDE.  It works, but it pulls in X11 dependencies
even for Wayland sessions.  `greetd` is a tiny, agnostic session manager; `tuigreet`
is its terminal UI front-end.  Together they start Hyprland directly with zero X11
overhead.  You can still run both greetd and SDDM on the same machine by switching
the `services.displayManager.sddm.enable` and `services.greetd.enable` flags.

### Catppuccin (Macchiato flavor)
Macchiato sits between Frappe (softer) and Mocha (darkest).  Catppuccin is the
practical choice here because the NixOS/HM ecosystem has excellent native package
support (`catppuccin-gtk`, `catppuccin-cursors`, per-app color palettes documented
everywhere).  Everforest is beautiful but requires copy-pasting color values into
every app by hand.

---

## Reading Order

1. **[01-system-module.md](./01-system-module.md)** — The NixOS-level module
   (`modules/system/desktop-hyprland.nix`).  System packages, greetd, portals, fonts,
   Wayland env vars.

2. **[02-home-module.md](./02-home-module.md)** — The Home Manager module
   (`modules/home/desktop-hyprland.nix`).  All user-space config: Hyprland, Waybar,
   Kitty, Fish, GTK theming, and everything else.

3. **[03-wiring-up.md](./03-wiring-up.md)** — How to connect the modules into your
   existing flake: `flake.nix`, `parts/nixos.nix`, host `configuration.nix`, host
   `home.nix`.

4. **[04-theming.md](./04-theming.md)** — Deeper look at theming options.  Catppuccin
   flavors, the `catppuccin/nix` flake shortcut, icon themes, cursor themes, and how
   GTK/Qt theming actually works.

5. **[05-troubleshooting.md](./05-troubleshooting.md)** — Common failure modes and
   how to diagnose them.

---

## Quick Orientation: What Goes Where

```
modules/system/desktop-hyprland.nix   NixOS module — root-owned config
modules/home/desktop-hyprland.nix     HM module    — user-owned config
parts/nixos.nix                        Wire both modules in
hosts/nixos1/configuration.nix         Flip the system enable flag
hosts/nixos1/home.nix                  Flip the home enable flag
```

The split matters because NixOS and Home Manager have different scopes:
- NixOS modules run as root and configure the system (installed programs, system
  services, PAM rules, fonts, environment variables visible to all users).
- Home Manager modules run as your user and manage dotfiles, user services, and
  per-program config under `~/.config`.

---

## Prerequisites

- The flake is already building cleanly with KDE.
- The wallpaper file exists at `nixos-config/media/ComicBookForest.png`.
- You are comfortable with `nixos-rebuild build --flake .` to test without switching.
