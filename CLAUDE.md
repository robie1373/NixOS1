# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: "Dry Dock"

Robie's NixOS fleet configuration. Goals: DRY, modular, flexible. Uses flake-parts to organize a multi-host NixOS + Home Manager setup.

**Assume planning mode always — do not make changes unless explicitly asked.**

## Key Commands

All run from `~/nixos-config/` on the target host:

```bash
# Apply config (shell alias)
rebuild        # → sudo nixos-rebuild switch --flake .#<hostname>

# Build without activating (check for errors)
build          # → nixos-rebuild build --flake .#<hostname>

# Test without making it the boot default
ntest          # → sudo nixos-rebuild test --flake .#<hostname>

# Update all flake inputs
nix flake update

# Rollback if something breaks
sudo nixos-rollback
git checkout flake.lock   # revert lock file
```

## Architecture

### Flake Structure

`flake.nix` is minimal — just inputs and a `flake-parts.lib.mkFlake` call that imports `parts/nixos.nix`.

`parts/nixos.nix` is where all hosts are defined via a `mkHost` helper:
```nix
mkHost = { system, modules }: inputs.nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs; };
  inherit system modules;
};
```

Each host in `flake.nixosConfigurations` lists its system modules and inline home-manager config (with per-user home module imports).

### Module Pattern

All feature modules use `mkEnableOption` + `mkIf`. Two namespaces:

- `mySystem.<featureName>.enable` — system modules (`modules/system/`)
- `myHome.<featureName>.enable` — home modules (`modules/home/`)

```nix
# system module example
options.mySystem.audio.enable = lib.mkEnableOption "PipeWire audio";
config = lib.mkIf config.mySystem.audio.enable { ... };

# home module example
options.myHome.mpv.enable = lib.mkEnableOption "mpv video player";
config = lib.mkIf config.myHome.mpv.enable { ... };
```

Hosts enable system features in `hosts/<name>/configuration.nix`:
```nix
mySystem.audio.enable           = true;
mySystem.desktopHyprland.enable = true;
```

Home features are enabled in `hosts/<name>/home.nix`:
```nix
myHome.mpv.enable    = true;
myHome.yazi.enable   = true;
```

System modules are listed in `parts/nixos.nix`, **not** in `configuration.nix`.

### Split: System vs Home

- `modules/system/` — NixOS system config (services, hardware, polkit, fonts)
- `modules/home/` — Home Manager config (dotfiles, user programs, shell)

Both halves must be listed separately in `parts/nixos.nix` — the system modules in the top-level `modules` list, the home modules inside the inline `home-manager.users.robie.imports` list.

### Home Manager Setup

- `useGlobalPkgs = true` and `useUserPackages = true` — pkgs comes from system nixpkgs
- `backupFileExtension = "backup"` — prevents activation failure when files exist (e.g. GTK files written by KDE)
- `allowUnfreePredicate` belongs in `modules/system/common.nix`, not in home modules (dead with useGlobalPkgs)
- Each host has its own `hosts/<name>/home.nix` containing only `home.stateVersion`

### Active Hosts

| Host | Arch | Notes |
|------|------|-------|
| flipper | x86_64 | Main laptop, disko disk encryption, FIDO2/TPM2 unlock |
| nixos1 | aarch64 | QEMU VM |

### Inputs

- `nixpkgs`: unstable branch
- `home-manager`: follows nixpkgs
- `flake-parts`: nixpkgs-lib follows nixpkgs
- `hyprland`: direct upstream (not from nixpkgs)
- `disko`: disk partitioning (used on flipper)

## Adding a New Host

1. Run `nixos-generate-config` on target → get `hardware-configuration.nix` + `stateVersion`
2. Copy `hardware-configuration.nix` to `hosts/<name>/`
3. Create `hosts/<name>/configuration.nix` (based on an existing host, set correct `stateVersion`, hostname, feature flags)
4. Create `hosts/<name>/home.nix` with correct `home.stateVersion`
5. Add `mkHost` block to `parts/nixos.nix` with appropriate system and home module lists

## guides/ Directory

The `guides/` directory is Robie's notebook and textbook for understanding the system. Treat it as a first-class deliverable alongside the code.

**Keep guides up to date when making changes.** If a config change affects something documented in guides/ (hardware behavior, a module's rationale, a workflow), update the relevant guide in the same session.

**Record planning in guides/ before new work.** When planning a new feature or investigating a problem, write up the plan, options considered, and reasoning in a new or existing guide file before implementing. This is the record of *why* decisions were made.

The `guides/` directory contains detailed reference docs — consult these before making hardware or desktop config changes:

- `guides/flipper/README.md` — hardware compatibility table for the ASUS Vivobook 14 Flip (flipper). Documents what works, what's broken, and why (speakers firmware, ISH accelerometer, media keys, NPU, etc.)
- `guides/flipper/03-disk-encryption.md` — LUKS + TPM2 + FIDO2/YubiKey setup
- `guides/hyprland/` — rationale for tool choices (greetd vs SDDM, foot vs kitty, Catppuccin) and troubleshooting
- `guides/apps/README.md` — app stack overview (mpv, zathura, imv, MPD/ncmpcpp, yazi, NAS mount)

**foot vs kitty:** VMs use `foot` (CPU-rendered, works everywhere). Physical hosts use `kitty` (GPU-accelerated, requires real OpenGL — fails on QEMU/KVM virtual GPUs).

## Adding a New Feature Module

1. Create `modules/system/<name>.nix` and/or `modules/home/<name>.nix`
2. Define `options.mySystem.<name>.enable = lib.mkEnableOption "..."` in the system module
3. Add the module file to the relevant host's module list in `parts/nixos.nix`
4. Enable it in `hosts/<hostname>/configuration.nix`
