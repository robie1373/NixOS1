# Switching flipper: Hyprland → KDE

## 1. Create `modules/_features/desktop-kde.nix`

The existing `modules/_system/desktop-kde.nix` uses the old `mkEnableOption` pattern.
Create a flat `_features/` version following the current convention (no option wrapper,
just unconditional config). The `_system/` one can stay as-is or be cleaned up later.

## 2. Edit `modules/hosts/flipper/default.nix`

- **Remove** `../../_features/desktop-hyprland.nix` from the modules list
- **Add** `../../_features/desktop-kde.nix` in its place
- **Remove** `../../_home/desktop-hyprland.nix` from `home-manager.users.robie.imports`

## 3. Check `hosts/flipper/configuration.nix` for Hyprland-specific leftovers

The Hyprland system module is unconditional so removing it from the list is enough —
but scan `configuration.nix` for anything added manually that references Hyprland
(none visible as of writing, just confirming).

## 4. Terminal: kitty comes from the Hyprland home module

`kitty` is configured in `_home/desktop-hyprland.nix`. Removing that module loses the
kitty config. Decide: add a standalone `_home/kitty.nix`, or rely on KDE's default
terminal (Konsole) for now.

## 5. Note the env vars being removed

`_features/desktop-hyprland.nix` sets `NIXOS_OZONE_WL=1`, `MOZ_ENABLE_WAYLAND=1`,
`QT_QPA_PLATFORM=wayland`. KDE Plasma 6 sets equivalent vars itself via the session —
no need to re-add them, but confirm after first login that Electron apps behave correctly.

## 6. Build

```bash
build   # nixos-rebuild build --flake .#flipper
```

## 7. Apply and reboot

**Do not use `nixos-rebuild switch` or `nh os switch` here.** When the activation runs,
systemd stops the old display manager (greetd) to start SDDM. This kills your Wayland
session — and the terminal running the switch command — mid-activation. The switch dies
incomplete and the system reboots, landing back on the old generation.

Instead, use `boot` to write the bootloader entry without activating anything live, then
reboot explicitly:

```bash
nh os boot .#flipper
# or: sudo nixos-rebuild boot --flake .#flipper
sudo reboot
```

SDDM should greet you instead of tuigreet. First login may be slow as KDE writes its
initial config files. The `backupFileExtension = "backup"` setting already in the config
handles any HM ↔ KDE file conflicts.

> **General rule for display manager switches:** always use `boot` + reboot when the
> switch involves changing `services.displayManager.*`. Running `switch` from within the
> old desktop session will kill that session before activation completes.

## 8. Verify

- [ ] SDDM greeter appears
- [ ] Plasma desktop loads (Wayland session recommended — choose at SDDM)
- [ ] 1Password unlocks (polkit is set in `_features/1password.nix`, independent of desktop)
- [ ] Audio works
- [ ] Bluetooth works (KDE has its own applet; blueman is gone)
- [ ] SD card reader works after first sleep/resume (the D3cold hook is desktop-agnostic)
