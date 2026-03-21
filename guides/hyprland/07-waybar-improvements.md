# Waybar — Widget Improvements

This guide documents the additions made to the right-side Waybar modules to make the bar feel like a complete system panel.

---

## What Was Added

| Module | What it shows | Interaction |
|---|---|---|
| `battery` | Charge %, charging state, time remaining | tooltip |
| `backlight` | Screen brightness % | scroll to adjust |
| `temperature` | CPU temperature | turns red at 80°C |
| `pulseaudio` | Volume % (updated) | click = pavucontrol, scroll = ±5% |
| `network` | SSID + signal % (updated) | click = nmtui in foot |
| `custom/power` | ⏻ button | click = rofi power menu |

**New module order (right side):**
```
battery · backlight · pulseaudio · network · temperature · cpu · memory · bluetooth · tray · custom/power
```

---

## Module Details

### Battery

Uses Waybar's built-in `battery` module. The `states` map directly to UPower thresholds configured in `hosts/flipper/configuration.nix` (`percentageLow=20`, `percentageCritical=10`). CSS applies different colors per state, and the critical state blinks.

Format icons cycle from empty to full based on charge level. Charging shows `⚡`, plugged-in-full shows ``.

### Backlight

Uses Waybar's `backlight` module, backed by `brightnessctl` (already installed). Scroll up/down on the widget adjusts brightness by 5% steps — same as the keyboard bindings but with a mouse.

### Temperature

Uses Waybar's `temperature` module with auto-detected hwmon path. On Lunar Lake this should find the `coretemp` readings automatically. If it shows `N/A`, the `hwmon-path` or `thermal-zone` may need to be pinned — check `ls /sys/class/hwmon/` and `cat /sys/class/hwmon/hwmon*/name`.

Turns red above 80°C.

### Pulseaudio (updated)

Added scroll-up/down using `wpctl` to adjust the default sink volume by 5% per scroll tick. Click still opens pavucontrol.

### Network (updated)

Now shows the SSID alongside signal strength instead of just a percentage. Click opens `nmtui` in a foot terminal for a quick connection switcher without leaving the keyboard workflow.

### Power Menu

A `custom/power` module with a ⏻ glyph. Clicking it opens a rofi dmenu with six options:

| Option | Action |
|---|---|
| Lock | `hyprlock` |
| Suspend | `systemctl suspend` |
| Hybrid Sleep | `systemctl hybrid-sleep` |
| Hibernate | `systemctl hibernate` |
| Reboot | `systemctl reboot` |
| Shutdown | `systemctl poweroff` |

The script is written inline as a Nix `writeShellScript` so it lands in the store and Waybar gets a stable path.

---

## CSS

New CSS rules added to the Waybar stylesheet:

- `#battery` — green normally, yellow at `warning`, red + blink at `critical`, blue when charging/plugged
- `#backlight` — yellow
- `#temperature` — green normally, red at `critical`
- `#custom-power` — red, slightly larger font, extra horizontal padding

---

## Troubleshooting

**Battery shows "N/A":** Run `ls /sys/class/power_supply/` — the module looks for a `BAT*` device. On this machine it should be `BAT0` or `BAT1`.

**Temperature shows "N/A":** Run `cat /sys/class/hwmon/hwmon*/name` to find the right sensor. If `coretemp` isn't auto-detected, pin `hwmon-path` explicitly:
```nix
temperature.hwmon-path = "/sys/class/hwmon/hwmon2/temp1_input"; # adjust index
```

**Power menu doesn't open:** Waybar's `on-click` runs with the user's PATH active. If rofi isn't found, use the full store path from `which rofi`.
