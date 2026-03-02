# Media Keys

**Status:** Configured. Most keys work; a few are EC-only with no OS hook.

---

## Key Map

| Key | Icon | Sends (evdev) | Mechanism | Status |
|---|---|---|---|---|
| F1 | Mute | `KEY_MUTE` on event0 | Hyprland `bindl` → `wpctl` | ✅ Working |
| F2 | Vol down | `KEY_VOLUMEDOWN` on event0 | Hyprland `bindel` → `wpctl` | ✅ Working |
| F3 | Vol up | `KEY_VOLUMEUP` on event0 | Hyprland `bindel` → `wpctl` | ✅ Working |
| F4 | Keyboard backlight | nothing | `asus-nb-wmi` drives sysfs directly | ✅ Working |
| F5 | Brightness down | nothing | `acpi_video` calls ACPI directly | ✅ Working |
| F6 | Brightness up | nothing | `acpi_video` calls ACPI directly | ✅ Working |
| F7 | Display / project | `Super+P` on event0 | EC-hardcoded; triggers Hyprland `$mod,P` (pseudotile) | ⚠️ See note |
| F8 | Smiley (MyASUS) | nothing | No OS events generated | ❌ Not bindable |
| F9 | Mic mute | nothing | `asus-nb-wmi` declares `KEY_MICMUTE` but never emits it | ❌ Not bindable |
| F10 | Mic (secondary) | nothing | No OS events generated | ❌ Not bindable |
| F11 | Rectangle/off | nothing | No OS events generated | ❌ Not bindable |
| F12 | ASUS icon | nothing | No OS events generated | ❌ Not bindable |

---

## How it works

**Volume and mute (F1–F3)** arrive on `event0` (AT keyboard, `asus-nb-wmi` routes them there)
with the correct Linux keycodes. Hyprland picks them up via `bindel`/`bindl` and calls `wpctl`.

**Brightness (F5–F6)** are intercepted by the `acpi_video` kernel module before they reach the
input layer. The BIOS `_BCM`/`_BQC` methods are called directly — no evdev event is generated,
no Hyprland binding is needed. Brightness visibly changes; `brightnessctl` can read/set the
same backlight independently.

**Keyboard backlight (F4)** is handled entirely by `asus-nb-wmi`, which writes to
`/sys/class/leds/asus::kbd_backlight/brightness` without generating an input event.

**F7** is hardcoded by the EC firmware to send `Super+P` (the Windows "Project" shortcut for
display mode switching). On Hyprland, `$mod, P` is bound to `pseudo` (dwindle pseudotile toggle),
so F7 toggles the active window's pseudotile state. This cannot be independently rebound without
changing what `$mod, P` does.

**F8–F12** generate no events at any level (evdev, ACPI, dmesg). The `asus-nb-wmi` driver
declares some of these keycodes (`KEY_MICMUTE`, etc.) in its input device capability list but
never emits them on this BIOS version. Binding them would require an ACPI SSDT override or a
kernel driver patch.

---

## NixOS config changes made

**`modules/home/desktop-hyprland.nix`** — added inside `wayland.windowManager.hyprland.settings`:

```nix
bindel = [
  ", XF86AudioRaiseVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@   5%+"
  ", XF86AudioLowerVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@   5%-"
  ", XF86MonBrightnessUp,   exec, brightnessctl set 10%+"
  ", XF86MonBrightnessDown, exec, brightnessctl set 10%-"
];

bindl = [
  ", XF86AudioMute,    exec, wpctl set-mute @DEFAULT_AUDIO_SINK@   toggle"
  ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
  ", XF86AudioPlay,    exec, playerctl play-pause"
  ", XF86AudioPause,   exec, playerctl play-pause"
  ", XF86AudioNext,    exec, playerctl next"
  ", XF86AudioPrev,    exec, playerctl previous"
];
```

Also added `playerctl` to `home.packages`.

**`modules/system/desktop-hyprland.nix`** — added udev rules so `brightnessctl` can write to
the backlight without root:

```nix
services.udev.packages = [ pkgs.brightnessctl ];
```

**`modules/system/common.nix`** — added robie to the `video` group (required by the udev rule
above):

```nix
extraGroups = [ "networkmanager" "wheel" "video" ];
```

---

## Debugging notes

- `wev` will show **no output** for bound keys — that's correct; Hyprland consumes them before
  forwarding to windows. Use `evtest /dev/input/event0` (needs root/nix-shell -p evtest) to
  see raw events.
- Volume/mute events appear on **event0** (AT keyboard), not event8 (asus-wmi). This is
  counterintuitive but confirmed via `evtest`.
- The `Asus WMI hotkeys` device (`event8`) registers capabilities but does not emit events for
  any key on this BIOS version. This is a firmware limitation, not a driver bug.
