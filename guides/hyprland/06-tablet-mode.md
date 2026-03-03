# Tablet Mode Workaround

Flipper is a 2-in-1. When folded into tablet mode there is no automatic
sensor, so rotation and input muting are triggered manually with a keybind.
This is a runtime-only workaround using `hyprctl keyword` — no permanent
config changes, no reboot needed.

---

## How it works

| Step | What happens |
|------|-------------|
| `Super + T` | Enter tablet mode |
| Screen rotates | `hyprctl keyword monitor eDP-1,preferred,auto,1,transform,1` |
| Keyboard + touchpad muted | Every device from `hyprctl devices` is disabled via `hyprctl keyword device:NAME:enabled false` |
| Waybar button updates | `custom/tablet` module in Waybar changes to show tablet icon |
| Tap the Waybar button | `tablet-exit` runs: re-enables devices, resets rotation |

The Waybar `custom/tablet` module is a two-way toggle — it calls `tablet-enter`
or `tablet-exit` depending on whether `/tmp/tablet-mode-devices` exists.
Both scripts send `pkill -RTMIN+8 waybar` to refresh the button state immediately.

Device names are saved to `/tmp/tablet-mode-devices` on entry and read back
on exit — so only exactly the devices that were disabled get re-enabled.

---

## Module location

`modules/home/tablet.nix` — enabled only on flipper via `hosts/flipper/home.nix`:

```nix
myHome.tablet.enable = true;
```

The module wires into Hyprland via `extraConfig` (not `settings`) to avoid
list-merge conflicts with the shared `desktop-hyprland` module.

> **Note:** Both `windowrulev2` and the old `windowrule` format are deprecated.
> Current syntax: `windowrule = rule on, match:title ^(name)$`

---

## Device list (flipper-specific)

Confirmed via `hyprctl devices -j` on flipper. The script targets only these
three — everything else stays enabled so tablet buttons, hotkeys, and Bluetooth
audio keep working.

| Device | Action |
|--------|--------|
| `at-translated-set-2-keyboard` | disabled |
| `ascp1205:00-093a:3020-touchpad` | disabled |
| `ascp1205:00-093a:3020-mouse` | disabled |
| `power-button` | disabled — on F-key bar, easy to hit accidentally |
| `sleep-button` | disabled — same reason |
| `intel-hid-5-button-array` | **left enabled** — likely volume rocker on F-key bar |
| `asus-wmi-hotkeys` | **left enabled** — brightness / fan / WMI events |
| `bose-qc-headphones-(avrcp)` | **left enabled** — Bluetooth media controls |

Note: this model has no bezel buttons. The F-key bar (power, volume, etc.) is
on the keyboard edge — not easily reachable when holding the tablet. Volume and
brightness are still adjustable via Bluetooth headphone controls or software.

---

## Scripts

Both scripts are in `home.packages` as `writeShellApplication` derivations.

### `tablet-enter`

```
hyprctl keyword monitor eDP-1,preferred,auto,1,transform,1
→ saves device names to /tmp/tablet-mode-devices
→ disables each device
→ spawns yad button in background
```

### `tablet-exit`

```
pkill yad
→ reads /tmp/tablet-mode-devices
→ re-enables each device
→ hyprctl keyword monitor eDP-1,preferred,auto,1,transform,0
```

---

## Known limitations

- **No auto-detection** — must press `Super + T` before folding the hinge.
- **External devices** — USB keyboards/mice are also disabled on entry.
- **Single monitor** — hardcoded to `eDP-1`; adjust if output name differs
  (check with `hyprctl monitors`).
- **Escape hatch** — if the yad button is accidentally closed, run
  `tablet-exit` from a terminal or another machine via SSH/Tailscale.
