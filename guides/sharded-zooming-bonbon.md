# Plan: Add Bluetooth Waybar Widget

## Context

Bluetooth is not currently enabled in the NixOS config for flipper. The user wants a
Waybar widget to show bluetooth status and manage devices (pair, connect, disconnect).

## Files to modify

1. `hosts/flipper/configuration.nix` — enable bluetooth hardware (device-specific)
2. `modules/system/desktop-hyprland.nix` — enable blueman daemon (desktop feature)
3. `modules/home/desktop-hyprland.nix` — Waybar module + CSS + package

---

## Changes

### 1. `hosts/flipper/configuration.nix`

Add after `networking.hostName`:

```nix
hardware.bluetooth.enable = true;
hardware.bluetooth.powerOnBoot = true;
```

`powerOnBoot` makes the adapter come up automatically on each boot.

### 2. `modules/system/desktop-hyprland.nix`

Add inside the `config = lib.mkIf ...` block:

```nix
# ── Bluetooth ────────────────────────────────────────────────────────────
services.blueman.enable = true;
```

This enables the blueman applet (systemd user service) and makes `blueman-manager`
available system-wide for device pairing/management.

### 3. `modules/home/desktop-hyprland.nix`

**a) Add `"bluetooth"` to `modules-right` before `"tray"`:**

```nix
modules-right = [ "pulseaudio" "network" "bluetooth" "cpu" "memory" "tray" ];
```

**b) Add bluetooth module config (after the `pulseaudio` block):**

```nix
bluetooth = {
  format                                   = "󰂯 {status}";
  format-connected                         = "󰂱 {device_alias}";
  format-connected-battery                 = "󰂱 {device_alias} {device_battery_percentage}%";
  tooltip-format                           = "{controller_alias}\t{controller_address}";
  tooltip-format-connected                 = "{controller_alias}\n\n{num_connections} connected\n{device_enumerate}";
  tooltip-format-enumerate-connected       = "  {device_alias}";
  tooltip-format-enumerate-connected-battery = "  {device_alias}\t{device_battery_percentage}%";
  on-click                                 = "blueman-manager";
};
```

Nerd Font icons used (already available via JetBrainsMono Nerd Font):
- `󰂯` = bluetooth (idle/off)
- `󰂱` = bluetooth connected

**c) Add CSS for `#bluetooth` (after the `#pulseaudio` line):**

```css
#bluetooth          { color: @blue;   padding: 0 8px; }
#bluetooth.connected { color: @green; }
#bluetooth.disabled  { color: @surface1; }
```

**d) No extra package needed** — `services.blueman.enable` puts `blueman-manager` on the
system PATH. Nothing to add to `home.packages`.

---

## Verification

After rebuild + reboot (hardware.bluetooth requires reboot):

1. `bluetoothctl show` — adapter should appear and be powered on
2. Waybar should show `󰂯 off` (or similar) in the status bar
3. Clicking the widget opens `blueman-manager`
4. Pair a device via blueman-manager; widget should update to `󰂱 <device name>`
