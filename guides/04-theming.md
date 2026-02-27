# Guide 04: Theming Deep Dive

The home module in Guide 02 gives you a complete, working Catppuccin Macchiato setup.
This guide explains how theming actually works in a Wayland/NixOS environment, what
your options are, and how to go further.

---

## How Desktop Theming Works on Linux

There are two independent theming systems that don't talk to each other:

**GTK** — used by most "Linux-native" apps: Nautilus, Thunar, GIMP, most system
dialogs, Firefox's chrome (not web content), LibreOffice.

**Qt** — used by KDE apps, VLC, OBS, many others.

Neither system has a universal config file.  Each reads its own environment variables
and config paths:

| System | Config location              | Environment variable       |
|--------|------------------------------|---------------------------|
| GTK3   | `~/.config/gtk-3.0/settings.ini` | `GTK_THEME`           |
| GTK4   | `~/.config/gtk-4.0/settings.ini` | `GTK_THEME`           |
| Qt5    | `~/.config/qt5ct/qt5ct.conf` | `QT_QPA_PLATFORMTHEME=qt5ct` |
| Qt6    | `~/.config/qt6ct/qt6ct.conf` | `QT_QPA_PLATFORMTHEME=qt6ct` |

Home Manager's `gtk` and `qt` options write these config files for you and set the
variables.  That's all they do — they're convenience wrappers around file generation.

---

## Catppuccin Flavors

Catppuccin has four flavors, all using the same accent colors but different background
darkness:

| Flavor     | Background | Character               |
|------------|------------|-------------------------|
| Latte      | `#eff1f5`  | Light mode               |
| Frappe     | `#303446`  | Muted dark               |
| Macchiato  | `#24273a`  | Medium dark (this config)|
| Mocha      | `#1e1e2e`  | Darkest                  |

To switch flavors, change every occurrence of `macchiato` in the home module to the
new flavor name, and update the hex color values.  The official color palette for all
flavors is at: https://github.com/catppuccin/catppuccin#-palette

**Accent colors** (mauve is used in this config):

| Name       | Macchiato hex |
|------------|---------------|
| Rosewater  | `#f4dbd6`     |
| Flamingo   | `#f0c6c6`     |
| Pink       | `#f5bde6`     |
| Mauve      | `#c6a0f6`     |
| Red        | `#ed8796`     |
| Maroon     | `#ee99a0`     |
| Peach      | `#f5a97f`     |
| Yellow     | `#eed49f`     |
| Green      | `#a6da95`     |
| Teal       | `#8bd5ca`     |
| Sky        | `#91d7e3`     |
| Sapphire   | `#7dc4e4`     |
| Blue       | `#8aadf4`     |
| Lavender   | `#b7bdf8`     |

---

## The `catppuccin/nix` Flake (Optional Shortcut)

The home module in Guide 02 manually specifies Catppuccin colors in each app.  There's
a flake that automates this: `github:catppuccin/nix`.

It provides a Home Manager module that adds a `catppuccin` option to programs that
support it.  Instead of copy-pasting hex values into every app config, you write:

```nix
catppuccin.flavor = "macchiato";
catppuccin.accent = "mauve";

programs.kitty.catppuccin.enable = true;
programs.fish.catppuccin.enable  = true;
programs.waybar.catppuccin.enable = true;
# etc.
```

Supported apps (as of early 2025): kitty, fish, bat, delta, starship, waybar, dunst,
hyprland, rofi, foot, ghostty, zsh, tmux, and more.

### Adding it to your flake

**`flake.nix` — add the input:**
```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  hyprland.url = "github:hyprwm/Hyprland";
  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  flake-parts = {
    url = "github:hercules-ci/flake-parts";
    inputs.nixpkgs-lib.follows = "nixpkgs";
  };
  catppuccin = {                          # ← add this block
    url = "github:catppuccin/nix";
  };
};
```

**`parts/nixos.nix` — add the HM module:**
```nix
home-manager.users.robie.imports = [
  ../hosts/nixos1/home.nix
  ../modules/home/common.nix
  ../modules/home/1password.nix
  ../modules/home/gemini-cli.nix
  ../modules/home/claude.nix
  ../modules/home/desktop-hyprland.nix
  inputs.catppuccin.homeManagerModules.catppuccin   # ← add this line
];
```

**In your home module**, you can then replace all the manual color blocks with:
```nix
catppuccin.flavor = "macchiato";
catppuccin.accent = "mauve";

programs.kitty.catppuccin.enable  = true;
programs.fish.catppuccin.enable   = true;
programs.waybar.catppuccin.enable = true;
services.dunst.catppuccin.enable  = true;
```

The trade-off: the flake approach is DRY and easy to update, but it's a black box —
you don't see the actual colors in your config.  The manual approach in Guide 02 is
more verbose but completely transparent.  Both are valid.

---

## Everforest (Alternative Theme)

Everforest is a nature-inspired green palette.  It doesn't have a NixOS/nix flake
equivalent of catppuccin/nix, so you configure it manually.

Key colors (dark medium variant):

| Role       | Hex       |
|------------|-----------|
| Background | `#2d353b` |
| Surface    | `#343f44` |
| Text       | `#d3c6aa` |
| Green      | `#a7c080` |
| Red        | `#e67e80` |
| Yellow     | `#dbbc7f` |
| Blue       | `#7fbbb3` |
| Purple     | `#d699b6` |
| Aqua       | `#83c092` |
| Orange     | `#e69875` |

The GTK theme package is `pkgs.everforest-gtk-theme` (check nixpkgs for the exact
attribute name — it has appeared under different names over time).

For Hyprland border colors with Everforest:
```nix
"col.active_border"   = "rgba(a7c080ff) rgba(7fbbb3ff) 45deg";
"col.inactive_border" = "rgba(343f44ff)";
```

---

## Icon Themes

**Papirus** is the recommended choice because it has good coverage, consistent style,
and the `catppuccin-papirus-folders` package recolors the folder icons to your accent
color:

```nix
home.packages = with pkgs; [
  papirus-icon-theme
  catppuccin-papirus-folders   # recolors Papirus folder icons
];

gtk.iconTheme = {
  name    = "Papirus-Dark";
  package = pkgs.papirus-icon-theme;
};
```

After installing, apply the folder recolor:
```bash
catppuccin-papirus-folders -C macchiato -a mauve
```

Other popular icon sets:
- `pkgs.tela-icon-theme` — clean, flat icons
- `pkgs.numix-icon-theme-circle` — rounded style
- `pkgs.fluent-icon-theme` — Windows 11 inspired

---

## Cursor Themes

The home module sets:
```nix
cursorTheme = {
  name    = "Catppuccin-Macchiato-Dark-Cursors";
  package = pkgs.catppuccin-cursors.macchiatoDark;
  size    = 24;
};
```

`pkgs.catppuccin-cursors` is a set of sub-packages.  Available attributes follow the
pattern `<flavor><Variant>`:
- `macchiatoDark`, `macchiatoLight`
- `mochaDark`, `mochaLight`
- `frappeDark`, `frappeLight`
- `latteDark`, `latteLight`

Other cursor options:
- `pkgs.nordzy-cursor-theme` — Nord palette
- `pkgs.volantes-cursors` — minimalist
- `pkgs.bibata-cursors` — popular, clean

> **Troubleshooting hint:** Cursor theme changes sometimes don't apply to XWayland apps
> (apps running via the X11 compatibility layer).  Fix by adding to `home.sessionVariables`:
> ```nix
> XCURSOR_THEME = "Catppuccin-Macchiato-Dark-Cursors";
> XCURSOR_SIZE  = "24";
> ```

---

## Fonts

### Nerd Fonts

The config uses `nerd-fonts.jetbrains-mono`.  Other popular choices in `pkgs.nerd-fonts`:

| Attribute           | Font name         | Character          |
|---------------------|-------------------|--------------------|
| `jetbrains-mono`    | JetBrainsMono     | Clean, wide        |
| `fira-code`         | FiraCode          | Ligatures          |
| `hack`              | Hack              | Classic mono       |
| `iosevka`           | Iosevka           | Narrow, tall       |
| `cascadia-code`     | CascadiaCode      | Microsoft's modern |
| `mononoki`          | Mononoki          | Quirky             |

Install multiple fonts safely — they don't conflict:
```nix
fonts.packages = with pkgs; [
  nerd-fonts.jetbrains-mono
  nerd-fonts.fira-code
  noto-fonts
  noto-fonts-emoji
];
```

`noto-fonts-emoji` is important — without it, emoji in web pages, notifications, and
terminals render as boxes.

### Changing the font in Waybar / Kitty / rofi

Each app references the font by its PostScript name.  After changing the Nerd Font,
update the `font-family` in Waybar's CSS, the `font.name` in Kitty's config, and the
`font` line in the rofi theme.  Run `fc-list` to see the exact names available.

---

## Waybar Customization

Waybar's layout and style are the most common things to tweak after initial setup.

### Changing position

```nix
programs.waybar.settings.mainBar.position = "bottom";  # or "left" / "right"
```

### Adding a battery widget (useful on laptops)

```nix
modules-right = [ "battery" "pulseaudio" "network" "cpu" "memory" "tray" ];

battery = {
  states = { warning = 30; critical = 15; };
  format = "{capacity}% {icon}";
  format-charging = "{capacity}%  ";
  format-icons = [ "" "" "" "" "" ];
};
```

### Hiding Waybar when a window is fullscreen

```nix
programs.waybar.settings.mainBar.layer = "top";
# Change to "overlay" if you want it always on top of fullscreen windows
```

---

## Hyprland Visual Tweaks

### Blur intensity

In the `decoration.blur` block:
```nix
size    = 5;    # blur radius (higher = more blurry, more GPU cost)
passes  = 2;    # number of blur passes (1 is cheap, 3+ is expensive)
```

### Disabling animations

If the VM feels sluggish, disable animations entirely:
```nix
animations.enabled = false;
```

### Window gaps

```nix
general = {
  gaps_in  = 5;   # gap between windows
  gaps_out = 10;  # gap between windows and screen edge
};
```

Set both to `0` for a dense, no-gap layout.

### Border gradient direction

```nix
"col.active_border" = "rgba(c6a0f6ff) rgba(8aadf4ff) 45deg";
#                                                       ^^^^
#                                          angle in degrees
```

Change `45deg` to `90deg` (top-to-bottom) or `180deg` (bottom-to-top).
Use a single color for no gradient: `"rgba(c6a0f6ff)"`.

---

## Applying Theme Changes Incrementally

You don't have to rebuild the whole system to see theme changes.  Home Manager can be
rebuilt independently:

```bash
# Just rebuild home-manager (much faster than full system rebuild)
home-manager switch --flake /home/robie/nixos-config#robie@nixos1
```

For live Waybar changes without even rebuilding, edit the generated CSS directly:
```bash
# Find the generated waybar config
cat ~/.config/waybar/style.css
# Edit it
# Then reload Waybar
pkill waybar && waybar &
```

Just remember any manual edits to `~/.config/` will be overwritten the next time you
run `nixos-rebuild switch`.  NixOS manages those files; treat the Nix source as the
source of truth.
