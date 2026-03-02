# Media Keys Setup

**Status:** Not configured yet — Hyprland bindings missing.

## Root Cause

The `asus-nb-wmi` + `intel_hid` drivers correctly generate XF86 keysyms for all Fn keys.
The kernel side works. The problem is the Hyprland config has **no `bindel`/`bindl` entries**,
so Hyprland silently discards the events.

Fn+F4 (mic mute) "works" because `asus-nb-wmi` toggles the mic LED and ALSA mute state at the
driver level — it requires no compositor involvement. All other keys (volume, brightness, media
player) need explicit Hyprland bindings.

---

## Changes Required

### 1. `modules/home/desktop-hyprland.nix` — Add media key bindings

Add inside `wayland.windowManager.hyprland.settings`, after the `bindm` block:

```nix
# Repeating locked binds — volume + brightness (work on lockscreen, repeat while held)
bindel = [
  ", XF86AudioRaiseVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@   5%+"
  ", XF86AudioLowerVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@   5%-"
  ", XF86MonBrightnessUp,   exec, brightnessctl set 10%+"
  ", XF86MonBrightnessDown, exec, brightnessctl set 10%-"
];

# Locked binds — mute + media player (work on lockscreen, no repeat)
bindl = [
  ", XF86AudioMute,    exec, wpctl set-mute @DEFAULT_AUDIO_SINK@   toggle"
  ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
  ", XF86AudioPlay,    exec, playerctl play-pause"
  ", XF86AudioPause,   exec, playerctl play-pause"
  ", XF86AudioNext,    exec, playerctl next"
  ", XF86AudioPrev,    exec, playerctl previous"
];
```

Also add `playerctl` to `home.packages`. `wpctl` is already available (ships with wireplumber).
`brightnessctl` is already in `home.packages`.

### 2. `modules/system/desktop-hyprland.nix` — Enable brightnessctl udev rules

```nix
services.udev.packages = [ pkgs.brightnessctl ];
```

Add inside the `config = lib.mkIf ... { }` block. Needed so the backlight devices are writable
by the `video` group. Without this, brightness keys silently do nothing.

### 3. `modules/system/common.nix` — Add robie to the `video` group

```nix
extraGroups = [ "networkmanager" "wheel" "video" ];
```

---

## Verification

After `rebuild`:

1. `groups robie` should include `video` (may need re-login for group to take effect)
2. Fn+F2/F3 → brightness changes; fallback: `brightnessctl set 10%+`
3. Volume Fn keys → volume changes; fallback: `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+`
4. If any key doesn't respond: `nix-shell -p wev --run wev` to confirm exact XF86 keysym names
