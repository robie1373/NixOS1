# Guide 03: Wiring It All Up

Now that both modules exist, you connect them to the flake.  This guide shows every
edit as a contextualized diff so you know exactly what to change and where.

---

## Overview of Changes

| File                                  | What changes                                      |
|---------------------------------------|---------------------------------------------------|
| `modules/system/desktop-hyprland.nix` | Already written in Guide 01 (replace the skeleton)|
| `modules/home/desktop-hyprland.nix`   | New file from Guide 02                            |
| `parts/nixos.nix`                     | Add both modules to the nixos1 module list        |
| `hosts/nixos1/configuration.nix`      | Add `mySystem.desktopHyprland.enable = true`      |
| `hosts/nixos1/home.nix`               | Add `myHome.desktopHyprland.enable = true`        |

No changes to `flake.nix` are required — all packages used in the modules come from
`nixpkgs`, which is already an input.

---

## 1. `parts/nixos.nix`

Add the new system and home modules to the nixos1 host.  The system module goes in the
top-level `modules` list alongside the other system modules.  The home module goes
inside the `home-manager.users.robie.imports` list.

**Before:**
```nix
nixos1 = mkHost {
  system = "aarch64-linux";
  modules = [
    ../hosts/nixos1/configuration.nix
    ../modules/system/common.nix
    ../modules/system/1password.nix
    ../modules/system/audio.nix
    ../modules/system/desktop-kde.nix
    ../modules/system/vm-guest.nix
    inputs.home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.robie.imports = [
        ../hosts/nixos1/home.nix
        ../modules/home/common.nix
        ../modules/home/1password.nix
        ../modules/home/gemini-cli.nix
        ../modules/home/claude.nix
      ];
    }
  ];
};
```

**After:**
```nix
nixos1 = mkHost {
  system = "aarch64-linux";
  modules = [
    ../hosts/nixos1/configuration.nix
    ../modules/system/common.nix
    ../modules/system/1password.nix
    ../modules/system/audio.nix
    ../modules/system/desktop-kde.nix
    ../modules/system/desktop-hyprland.nix     # ← add this line
    ../modules/system/vm-guest.nix
    inputs.home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.robie.imports = [
        ../hosts/nixos1/home.nix
        ../modules/home/common.nix
        ../modules/home/1password.nix
        ../modules/home/gemini-cli.nix
        ../modules/home/claude.nix
        ../modules/home/desktop-hyprland.nix   # ← add this line
      ];
    }
  ];
};
```

Both modules are guarded by their `mkIf` options, so adding them here doesn't change
the build until you flip the enable flags in the next two steps.

---

## 2. `hosts/nixos1/configuration.nix`

Add the enable flag for the system module.  You can keep `desktopKde.enable = true`
for now — both desktops can coexist.  greetd will give you a session selector.  When
you're confident about Hyprland, set `desktopKde.enable = false` to drop SDDM and KDE.

**Before:**
```nix
mySystem.audio.enable      = true;
mySystem.desktopKde.enable = true;
mySystem.vmGuest.enable    = true;
```

**After:**
```nix
mySystem.audio.enable           = true;
mySystem.desktopKde.enable      = true;   # set to false once Hyprland is working
mySystem.desktopHyprland.enable = true;   # ← add this line
mySystem.vmGuest.enable         = true;
```

**Conflict note:** `services.greetd.enable` (from our module) and
`services.displayManager.sddm.enable` (from desktop-kde.nix) both try to own the
display manager slot.  NixOS will throw a build error if both are enabled at the same
time.  There are two ways to handle this:

**Option A — disable KDE's display manager but keep KDE packages:**
In `modules/system/desktop-kde.nix`, change `services.displayManager.sddm.enable = true`
to `services.displayManager.sddm.enable = false`.  KDE is still installed and can be
launched from greetd's session list.

**Option B — disable KDE entirely:**
Set `mySystem.desktopKde.enable = false` in `configuration.nix`.  Hyprland only.

For a clean Hyprland-only machine, Option B is simpler.  For a machine where you want
both available, do Option A.

---

## 3. `hosts/nixos1/home.nix`

Add the enable flag for the home module.

**Before:**
```nix
{ ... }:
{
  home.stateVersion = "25.11";
}
```

**After:**
```nix
{ ... }:
{
  home.stateVersion = "25.11";

  myHome.desktopHyprland.enable = true;   # ← add this line
}
```

---

## 4. Test Before Switching

Always build first to catch Nix errors without touching your running system:

```bash
cd /home/robie/nixos-config
nixos-rebuild build --flake .#nixos1
```

If it builds cleanly, a `result` symlink appears in the current directory pointing to
the built system closure.  You can inspect it:

```bash
ls result/
```

When you're happy, apply it:

```bash
sudo nixos-rebuild switch --flake .#nixos1
```

If something breaks, roll back immediately:

```bash
sudo nixos-rollback
```

Or choose the previous generation at the boot menu (NixOS keeps them all).

---

## 5. First Boot into Hyprland

After switching, the next login will go through `tuigreet` instead of SDDM.  You'll
see a minimal text interface.  Enter your username and password.  If you have both KDE
and Hyprland installed, tuigreet shows a session selector (press Tab or use `--list-sessions`).

Once inside Hyprland:

| Action                | Key / Command                  |
|-----------------------|-------------------------------|
| Open terminal         | `SUPER + Return`               |
| Open app launcher     | `SUPER + D`                    |
| Close window          | `SUPER + Q`                    |
| Switch workspace      | `SUPER + 1` through `SUPER + 5`|
| Move window to WS     | `SUPER + SHIFT + 1` etc.       |
| Toggle floating       | `SUPER + V`                    |
| Fullscreen            | `SUPER + F`                    |
| Exit Hyprland         | `SUPER + M`                    |

---

## 6. Confirming Services Started

From a Kitty terminal, check that background services are running:

```bash
# Hyprland background processes
hyprctl clients        # list open windows
hyprctl monitors       # confirm monitor config was applied
hyprctl activewindow   # current focused window

# User services started by exec-once
pgrep -a waybar
pgrep -a dunst
pgrep -a hyprpaper
pgrep -a hypridle

# Portal
systemctl --user status xdg-desktop-portal
systemctl --user status xdg-desktop-portal-hyprland
```

If a service didn't start, you can start it manually to see the error:
```bash
waybar &         # runs in foreground, shows errors
hyprpaper &
```

---

## 7. Setting Fish as Default Shell (Optional)

The system module enables Fish, but your login shell is still whatever was set in
`common.nix`.  To make Fish the default interactive shell, add to
`hosts/nixos1/configuration.nix` or `modules/system/common.nix`:

```nix
users.users.robie.shell = pkgs.fish;
```

You'll also need `pkgs` in scope — check whether your common.nix already has
`{ pkgs, ... }:` in its function arguments; if not, add it.

---

## What Each File Owns (Summary)

```
modules/system/desktop-hyprland.nix
  └─ programs.hyprland.enable
  └─ programs.fish.enable
  └─ services.greetd
  └─ xdg.portal
  └─ security.pam.services.hyprlock
  └─ fonts.packages
  └─ environment.sessionVariables

modules/home/desktop-hyprland.nix
  └─ wayland.windowManager.hyprland  ← the actual hyprland.conf
  └─ programs.waybar
  └─ programs.rofi
  └─ services.dunst
  └─ services.hyprpaper
  └─ services.hypridle
  └─ programs.hyprlock
  └─ programs.foot
  └─ programs.fish
  └─ gtk / qt theming
  └─ home.packages (wl-clipboard, grim, etc.)

hosts/nixos1/configuration.nix
  └─ mySystem.desktopHyprland.enable = true   ← your on/off switch

hosts/nixos1/home.nix
  └─ myHome.desktopHyprland.enable = true     ← your on/off switch
```
