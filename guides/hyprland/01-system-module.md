# Guide 01: The System Module

**File:** `modules/system/desktop-hyprland.nix`

This module already exists as a skeleton.  You're filling it out.  Everything here
runs at the NixOS system level — it requires root to apply and affects all users.

---

## Full Module Content

```nix
{ lib, config, pkgs, ... }:

{
  options.mySystem.desktopHyprland.enable =
    lib.mkEnableOption "Hyprland desktop";

  config = lib.mkIf config.mySystem.desktopHyprland.enable {

    # ── Compositor ──────────────────────────────────────────────────────────
    programs.hyprland.enable = true;

    # ── Shell ────────────────────────────────────────────────────────────────
    programs.fish.enable = true;

    # ── Display manager ──────────────────────────────────────────────────────
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
          user = "greeter";
        };
      };
    };

    # ── Desktop portal ───────────────────────────────────────────────────────
    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-hyprland
        pkgs.xdg-desktop-portal-gtk      # needed for GTK file pickers
      ];
      config.common.default = "*";
    };

    # ── Screen locker PAM rule ───────────────────────────────────────────────
    security.pam.services.hyprlock = {};

    # ── Polkit ───────────────────────────────────────────────────────────────
    security.polkit.enable = true;

    # ── Fonts ─────────────────────────────────────────────────────────────────
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono    # glyphs used by Waybar and rofi
      noto-fonts
      noto-fonts-emoji
    ];

    # ── Wayland compatibility env vars ───────────────────────────────────────
    environment.sessionVariables = {
      NIXOS_OZONE_WL   = "1";            # Electron apps (VS Code, etc.)
      QT_QPA_PLATFORM  = "wayland";      # Qt apps
      MOZ_ENABLE_WAYLAND = "1";          # Firefox
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE    = "wayland";
    };

  };
}
```

---

## Section-by-Section Explanation

### `programs.hyprland.enable = true`

This NixOS option does several things at once:

- Installs the Hyprland compositor package
- Sets up the necessary PAM session rules
- Installs Hyprland's `hyprctl` CLI tool
- Creates the Wayland session file that greetd (or SDDM) can discover
- Enables the required kernel module for DRM leasing

You still write the Hyprland *config* (keybinds, monitor layout, decorations) in the
Home Manager module.  This option is just the system-level plumbing.

---

### `programs.fish.enable = true`

Fish needs to be enabled at the **system level** so it gets added to `/etc/shells`.
That file is the list of valid login shells; if Fish isn't in it, you can't set it as
your default shell via `users.users.robie.shell = pkgs.fish`.

You configure Fish's behaviour (aliases, greeting, prompts) in the Home Manager module.
This line just says "Fish is a real shell on this machine."

---

### `services.greetd`

`greetd` is a minimal, compositor-agnostic session manager.  It replaces SDDM for a
pure-Wayland boot sequence.

```nix
command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
user = "greeter";
```

- `tuigreet` is a terminal-based greeter that runs in the TTY before Hyprland starts.
- `--time` shows a clock.
- `--remember` saves the last-used username so you don't have to type it every time.
- `--cmd Hyprland` is the command greetd runs after a successful login.
- `user = "greeter"` is a system user greetd creates automatically.

**Coexisting with KDE/SDDM:**  You can only have one active display manager at a time.
If `mySystem.desktopKde.enable = true` is also set, `services.displayManager.sddm.enable`
and `services.greetd.enable` will conflict.  The simplest fix is to wrap them so they're
mutually exclusive, or just set one to `false` in `configuration.nix`.

**Alternative greeter:**  `tuigreet` is text-only.  If you want a graphical greeter
that shows the wallpaper, look at `regreet` (GTK4, Wayland-native) or
`greetd-gtkgreet`.  `tuigreet` is used here for simplicity and speed.

---

### `xdg.portal`

Desktop portals are a D-Bus API layer that lets sandboxed apps (Flatpak, or anything
using the XDG portal spec) do things like:

- Open a file picker
- Take a screenshot or share a screen
- Trigger notifications
- Request location data

Without a portal, apps like OBS, Discord screen share, and many Electron apps will
fail silently or show errors.

`xdg-desktop-portal-hyprland` implements the Hyprland-specific parts (screensharing
uses the wlr protocol, which Hyprland supports).  `xdg-desktop-portal-gtk` handles
the GTK file picker dialog that most apps expect.

`config.common.default = "*"` tells the portal system to use the first available
portal implementation for any request type it doesn't have a specific rule for.

> **Troubleshooting hint:** If an app complains "portal not available" or screensharing
> is broken, check `journalctl --user -u xdg-desktop-portal` and
> `journalctl --user -u xdg-desktop-portal-hyprland`.  The portal services start
> automatically when Hyprland launches but sometimes race with app startup — a short
> `sleep 2` before the app in `exec-once` fixes race conditions.

---

### `security.pam.services.hyprlock = {}`

This creates a PAM (Pluggable Authentication Modules) entry for Hyprlock.  PAM is how
Linux authenticates users for things other than login — sudo, screen lockers, ssh keys.

Without this line, Hyprlock will show the lock screen but won't be able to verify your
password.  You'll be locked out.  This is a common gotcha.

---

### `security.polkit.enable = true`

Polkit handles privilege escalation for desktop apps — things like mounting drives,
managing network connections, or changing system settings without a full `sudo` prompt.
Many Wayland compositors need it running.  It was probably already enabled through
another module, but being explicit is safe.

---

### `fonts.packages`

```nix
nerd-fonts.jetbrains-mono
```

Nerd Fonts are regular fonts patched to include thousands of icon glyphs (from Font
Awesome, Material Design Icons, Powerline, etc.).  Waybar and rofi use these glyphs
for the icons in the status bar and launcher.

**Note on package names:** The nixpkgs attribute changed in 2024.  The new style is
`pkgs.nerd-fonts.jetbrains-mono` (a sub-attribute).  The old style
`pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; }` still works in nixpkgs-unstable
but is deprecated.  If you get a build error, try the old style:

```nix
(pkgs.nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
```

After switching, verify the font installed with:
```bash
fc-list | grep JetBrains
```

---

### `environment.sessionVariables`

These variables are set for every session on the machine, before any user shell starts.

| Variable              | Effect                                                     |
|-----------------------|------------------------------------------------------------|
| `NIXOS_OZONE_WL=1`   | Tells Electron apps (VS Code, Discord) to use Wayland      |
| `QT_QPA_PLATFORM=wayland` | Tells Qt5/Qt6 apps to use the Wayland backend          |
| `MOZ_ENABLE_WAYLAND=1`| Tells Firefox to use the native Wayland backend            |
| `XDG_CURRENT_DESKTOP` | Tells apps which desktop they're running under             |
| `XDG_SESSION_TYPE`    | Tells apps (and portals) this is a Wayland session         |

Without `QT_QPA_PLATFORM=wayland`, Qt apps may launch in XWayland (the X11
compatibility layer) and look blurry on HiDPI or have input lag.

> **Troubleshooting hint:** If a specific app ignores these and runs under XWayland
> anyway, you can override per-app by wrapping its exec command:
> `env QT_QPA_PLATFORM=wayland my-qt-app`

---

## What This Module Does NOT Do

It does not:
- Configure Hyprland's keybinds, monitor layout, or appearance → that's the HM module
- Install user apps (Kitty, rofi, waybar) → those are HM packages
- Set up the GTK or cursor theme → HM module
- Enable Fish as your *default shell* → that goes in `common.nix` or `configuration.nix`
  (`users.users.robie.shell = pkgs.fish`)

---

## Setting Fish as Your Default Shell

If you want Fish to actually be your login shell (rather than just available), add this
to `modules/system/common.nix` or `hosts/nixos1/configuration.nix`:

```nix
users.users.robie.shell = pkgs.fish;
```

This requires `programs.fish.enable = true` to have run first (which our system module
does), so the ordering is handled by NixOS's module system automatically.
