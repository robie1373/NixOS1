# Runbook: Add a Feature Module

Use this for any new `mySystem.<name>` or `myHome.<name>` module.

---

## System module (`modules/system/<name>.nix`)

**1. Create the file**

```nix
# modules/system/<name>.nix
{ lib, config, pkgs, ... }:
{
  options.mySystem.<name>.enable = lib.mkEnableOption "<short description>";

  config = lib.mkIf config.mySystem.<name>.enable {
    # NixOS options here
  };
}
```

**2. Add to `parts/nixos.nix`** — in the `modules = [ ... ]` list for each host that should have it:

```nix
flipper = mkHost {
  modules = [
    ...
    ../modules/system/<name>.nix   # ← add here
    ...
  ];
};
```

> **Gotcha:** If you forget this step, the option won't exist and you'll get `attribute '<name>' missing` when evaluating the flake. The module file must be in `parts/nixos.nix` — listing it only in `configuration.nix` does nothing.

**3. Enable in `hosts/<hostname>/configuration.nix`**

```nix
mySystem.<name>.enable = true;
```

**4. Build and verify**

```bash
build    # nixos-rebuild build --flake .#<hostname>
```

---

## Home module (`modules/home/<name>.nix`)

**1. Create the file**

```nix
# modules/home/<name>.nix
{ lib, config, pkgs, ... }:
{
  options.myHome.<name>.enable = lib.mkEnableOption "<short description>";

  config = lib.mkIf config.myHome.<name>.enable {
    # Home Manager options here
  };
}
```

> **Gotcha — unfree packages:** Do NOT add `allowUnfreePredicate` in a home module. With `useGlobalPkgs = true`, home modules inherit the system nixpkgs instance. The predicate lives in `modules/system/common.nix` only.

> **Gotcha — terminal choice:** VMs use `foot` (CPU-rendered, works on QEMU). Physical hosts use `kitty` (GPU-accelerated, fails on virtual GPUs). If your module sets a terminal, parameterize it or keep it host-specific.

**2. Add to `parts/nixos.nix`** — in the `home-manager.users.robie.imports = [ ... ]` list for each host:

```nix
home-manager.users.robie.imports = [
  ...
  ../modules/home/<name>.nix   # ← add here
  ...
];
```

> **Gotcha:** Same as system modules — the import must be in `parts/nixos.nix`. Listing it in `home.nix` does nothing.

**3. Enable in `hosts/<hostname>/home.nix`**

```nix
myHome.<name>.enable = true;
```

**4. Build and verify**

```bash
build
```

---

## Adding a new flake input

If the module depends on an external flake input (e.g. a new upstream package):

**1. Add to `flake.nix` inputs:**

```nix
inputs = {
  ...
  <input-name> = {
    url = "github:owner/repo";
    inputs.nixpkgs.follows = "nixpkgs";  # only if the input accepts it
  };
};
```

**2. Pass through `parts/nixos.nix`** — `mkHost`/`mkServer` already passes `inputs` via `specialArgs`, so the module receives it automatically. Reference it as `inputs.<input-name>` inside the module.

**3. Update flake lock:**

```bash
nix flake update <input-name>   # update just that input
# or
nix flake update                # update all inputs
```

---

## Skeleton: minimal system module

```nix
{ lib, config, pkgs, ... }:
{
  options.mySystem.CHANGEME.enable = lib.mkEnableOption "CHANGEME description";

  config = lib.mkIf config.mySystem.CHANGEME.enable {

  };
}
```

## Skeleton: minimal home module

```nix
{ lib, config, pkgs, ... }:
{
  options.myHome.CHANGEME.enable = lib.mkEnableOption "CHANGEME description";

  config = lib.mkIf config.myHome.CHANGEME.enable {

  };
}
```

---

## Wayland Input Methods (fcitx5)

Hard-won lessons from the Korean/Hangul fcitx5 setup on Hyprland.

### 1. `i18n.inputMethod` does NOT autostart on Hyprland

`i18n.inputMethod` creates an XDG autostart `.desktop` file. Hyprland does not
process XDG autostart entries. Without a systemd user service, the daemon never starts.

**Required addition in the NixOS module alongside `i18n.inputMethod`:**

```nix
systemd.user.services.fcitx5 = {
  description = "Fcitx5 input method daemon";
  partOf      = [ "graphical-session.target" ];
  wantedBy    = [ "graphical-session.target" ];
  after       = [ "graphical-session.target" ];
  serviceConfig = {
    Type       = "simple";          # foreground — do NOT use -d (daemon flag)
    ExecStart  = "${config.i18n.inputMethod.package}/bin/fcitx5 --replace";
    Restart    = "on-failure";
    RestartSec = 1;
  };
};
```

Use `config.i18n.inputMethod.package` — not `pkgs.fcitx5` — to get the
addon-wrapped binary built from your addon list. Do NOT pass `-d`; `Type=simple`
requires the process to stay in the foreground.

### 2. Modifier keys cannot be IM trigger keys on Wayland

fcitx5's `TriggerKeys` mechanism works by intercepting key events via the Wayland
input method protocol. This protocol only delivers events when a text input context
is focused, and **modifier-only keypresses (Alt_R, Caps_Lock, Shift, etc.) are
tracked as keyboard state — they are never forwarded to the IM**.

Setting `TriggerKeys = "Alt_R"` or `TriggerKeys = "Caps_Lock"` in fcitx5 config
will silently do nothing on Wayland.

**Fix: intercept the key at the Hyprland compositor level instead:**

```nix
# In wayland.windowManager.hyprland.settings.bind:
", Alt_R, exec, ${pkgs.fcitx5}/bin/fcitx5-remote -t"
```

Hyprland consumes the keypress before any app sees it and calls `fcitx5-remote -t`
to toggle the IM state. Clear `TriggerKeys` in fcitx5 config (it's unused).

### 3. `korean:hangul_capslock` is not a valid xkb option

It does not exist in xkeyboard-config. Using it silently does nothing.

### 4. Use `fcitx5.waylandFrontend`, don't just omit `GTK_IM_MODULE`

fcitx5 on Wayland uses the native text-input-v3 protocol. Setting `GTK_IM_MODULE=fcitx`
conflicts with this and causes fcitx5's own Wayland Diagnose to warn.

**Gotcha (found 2026-06-23):** omitting `GTK_IM_MODULE` from your own
`environment.sessionVariables` is *not* enough. The NixOS `i18n.inputMethod`
fcitx5 module exports `GTK_IM_MODULE` **and** `QT_IM_MODULE` itself, via
`environment.variables`, whenever `waylandFrontend = false` (the default) — see
`nixos/modules/i18n/input-method/fcitx5.nix`, the `lib.optionalAttrs
(!cfg.waylandFrontend)` block. You can't unset what the module sets by leaving it
out of your config.

The fix is to set `i18n.inputMethod.fcitx5.waylandFrontend = true;`. The module
then skips both vars and fcitx uses the Wayland frontend. Re-add `QT_IM_MODULE =
"fcitx"` and `XMODIFIERS = "@im=fcitx"` explicitly in `sessionVariables` for
Qt5/XWayland apps; leave `GTK_IM_MODULE` unset. Verify after a rebuild with
`grep IM_MODULE /etc/set-environment` — `GTK_IM_MODULE` should be absent.
