# Multi-Host Module Sharing

## Where do modules actually live right now?

All feature modules live in `modules/system/` and `modules/home/`. Host directories contain only:

| File | Purpose |
|------|---------|
| `hosts/<name>/configuration.nix` | Hostname, feature flags (`mySystem.*.enable = true`), hardware quirks, stateVersion |
| `hosts/<name>/home.nix` | Home feature flags (`myHome.*.enable = true`), home.stateVersion |
| `hosts/<name>/hardware-configuration.nix` | Auto-generated, never edited |
| `hosts/<name>/disko.nix` | Disk layout — flipper only |

Nothing in `hosts/` defines a module. Modules are defined once in `modules/` and imported by hosts via `parts/nixos.nix`. The host files only *set option values* — they don't contain logic.

This is already the correct architecture. There is no duplication of module logic across hosts.

---

## Standard NixOS pattern for multi-host sharing in a flake config

The repo is already following the standard pattern:

1. **Feature modules in `modules/`** — each module is defined exactly once with `mkEnableOption` + `mkIf`
2. **Imported per-host in the flake** — `parts/nixos.nix` lists which modules each host uses
3. **Activated per-host in `hosts/<name>/`** — hosts set `mySystem.*.enable = true` for the features they want

This is the idiomatic approach used by most production NixOS flake configs. The key insight is that *importing* a module and *enabling* it are separate steps — a module can be imported (making its option available) without being activated (by leaving enable at its false default).

### What some larger configs do differently

For reference, as a fleet grows beyond ~5 hosts, some configs introduce:

- **Profile modules** — a module that enables a standard bundle of options (`profiles/desktop.nix` sets `mySystem.audio.enable = true; mySystem.desktopHyprland.enable = true; ...`). This repo doesn't need this yet.
- **`lib/` helpers** — shared functions for generating host configs. This repo uses `mkHost`/`mkServer` in `parts/nixos.nix` which serves the same purpose at current scale.

Neither is needed here.

---

## What changes (if any) are needed for a second host?

**None required.** `nixos1` already exists as a second host and shares modules cleanly with `flipper`.

### One housekeeping improvement: DRY the module lists

Currently `parts/nixos.nix` lists ~15 modules for each desktop host. As a third or fourth host is added, this repetition becomes noise. The fix is a `let` binding for the common set:

```nix
{ inputs, ... }:
let
  mkHost = ...;
  mkServer = ...;

  # Modules imported by every desktop host
  desktopSystemModules = [
    ../modules/system/common.nix
    ../modules/system/1password.nix
    ../modules/system/audio.nix
    ../modules/system/desktop-hyprland.nix
  ];

  desktopHomeModules = [
    inputs.nix-index-database.hmModules.nix-index
    ../modules/home/common.nix
    ../modules/home/1password.nix
    ../modules/home/bearing.nix
    ../modules/home/desktop-hyprland.nix
    ../modules/home/claude.nix
    ../modules/home/gemini-cli.nix
    ../modules/home/firefox.nix
    ../modules/home/yazi.nix
    ../modules/home/hyprshot.nix
  ];
in
{
  flake.nixosConfigurations = {

    flipper = mkHost {
      system = "x86_64-linux";
      modules = desktopSystemModules ++ [
        ../hosts/flipper/configuration.nix
        ../modules/system/nas.nix
        ../modules/system/speaker-fix.nix
        ../modules/system/gaming.nix
        inputs.disko.nixosModules.disko
        ../hosts/flipper/disko.nix
        inputs.home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.robie.imports = desktopHomeModules ++ [
            ../hosts/flipper/home.nix
            ../modules/home/obsidian.nix
            ../modules/home/tablet.nix
            ../modules/home/mpv.nix
            ../modules/home/zathura.nix
            ../modules/home/imv.nix
            ../modules/home/mpd.nix
            ../modules/home/nas.nix
            ../modules/home/anki-bin.nix
          ];
        }
      ];
    };

    nixos1 = mkHost {
      system = "aarch64-linux";
      modules = desktopSystemModules ++ [
        ../hosts/nixos1/configuration.nix
        ../modules/system/vm-guest.nix
        inputs.home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.robie.imports = desktopHomeModules ++ [
            ../hosts/nixos1/home.nix
            ../modules/home/obsidian.nix
          ];
        }
      ];
    };

  };
}
```

Each new desktop host then only lists its *additions* to the common set, not the full list.

### When to do this

Not yet — two hosts is fine as-is. Do this when adding a third desktop host, or when the repetition in `parts/nixos.nix` is actively causing confusion.

---

## Summary

| Question | Answer |
|----------|--------|
| Where do modules live? | `modules/system/` and `modules/home/` — already shared, not per-host |
| Standard multi-host pattern? | Already in use: modules in `modules/`, imported in flake, activated per-host via options |
| Changes needed for a second host? | None — `nixos1` proves it already works |
| Recommended path forward? | Add `desktopSystemModules`/`desktopHomeModules` let-bindings in `parts/nixos.nix` when a third desktop host is added |
