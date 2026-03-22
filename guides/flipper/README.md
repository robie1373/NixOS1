# flipper — Hardware Reference

**Machine:** ASUS Vivobook 14 Flip TP3407SA-DS74T
**CPU:** Intel Core Ultra 7 256V (Lunar Lake)
**Kernel:** 6.18.15 · **Tested:** 2026-03-02

This document covers what works, what doesn't, why each thing behaves the way it does,
and what NixOS config changes fix the broken parts.

## TODO list
A tracked [TODO list](todo.md) for keeping track of tasks.
## Guides

- **[01-speakers-fix.md](./01-speakers-fix.md)** — TAS2781 firmware name mismatch fix
- **[02-media-keys.md](./02-media-keys.md)** — Fn key map, working keys, Hyprland bindings
- **[03-disk-encryption.md](./03-disk-encryption.md)** — LUKS plan, TPM2+PIN, YubiKey FIDO2, YubiKey Bio analysis, reinstall overview

---

## At a Glance

| Component | Status | Notes |
|---|---|---|
| CPU / GPU (Arc 140V) | ✅ Working | `xe` driver |
| Display + backlight | ✅ Working | eDP, `intel_backlight`, max 400 |
| Keyboard | ✅ Working | |
| Touchpad | ✅ Working | Pixart ASCP1205, full multi-touch |
| Touchscreen + stylus | ✅ Working | Ilitek ILIT2901, multi-touch + pen |
| Media / Fn keys | ⚠️ Partial | F1–F6 working; F7=Super+P; F8–F12 no OS events — see [02-media-keys.md](./02-media-keys.md) |
| Keyboard backlight | ✅ Working | 4 levels via `asus::kbd_backlight` |
| WiFi (Intel BE201, Wi-Fi 7) | ✅ Working | firmware v101 |
| Bluetooth | ✅ Needs one line | hardware ready, service not enabled |
| Audio (headphone / mic / HDMI) | ✅ Working | SOF fw v2.13.0.1 |
| Internal speakers | ❌ Broken | TAS2781 firmware name mismatch — fixable |
| Webcam (FHD) | ✅ Working | `/dev/video0-1`, `uvcvideo` |
| NPU (Intel VPU / 48 TOPS) | ✅ Working | `intel_vpu`, `/dev/accel/accel0` |
| Battery + USB-C charging | ✅ Working | UCSI, 2 ports |
| Thunderbolt 4 | ✅ Working | |
| NVMe (WD SN5000S) | ✅ Working | |
| SD card reader (GL9750) | ⚠️ Detected | not yet tested |
| Screen auto-rotation | ❌ Broken | Intel ISH firmware rejected — no fix yet |
| IR camera | ⚠️ Unknown | IPU6 pipeline not configured |
| Fingerprint reader | — | not present on this SKU |
| Fan curve control | ⚠️ N/A | WMI method missing from BIOS |

---

## Hardware Overview

### CPU — Intel Core Ultra 7 256V (Lunar Lake)

Lunar Lake is Intel's 2024 "all on package" design.  The CPU, GPU, NPU, and 32 GB
of LPDDR5X memory are all integrated into a single package — there are no DIMM slots.
The architecture is a significant departure from previous Intel generations:

- **CPU cores:** 4 Lion Cove (performance) + 4 Skymont (efficiency)
- **GPU:** Intel Arc 140V, 8 Xe2-cores — driver `xe` (the newer DRM driver, not `i915`)
- **NPU:** NPU4 (48 TOPS) — separate die, driver `intel_vpu`
- **Memory:** 16 GB LPDDR5X on-package, not user-upgradeable

The `xe` GPU driver replaces the old `i915` for Lunar Lake.  This matters if you see
any guides or forum posts referencing `/sys/class/drm/i915_*` paths — those won't
exist.  Use `/sys/class/drm/card0*` and look for the `xe` module.

---

## Input

### Touchpad

The touchpad is a **Pixart ASCP1205** (HID `093A:3020`) connected over I2C and driven
by the `hid-multitouch` kernel module.  It works out of the box including multi-finger
gestures.  Hyprland and libinput pick it up automatically.

### Touchscreen and Stylus

The touchscreen is an **Ilitek ILIT2901** (HID `222A:5530`), also on I2C.  It registers
as two separate input devices — touch (multi-touch) and stylus — both managed by
`hid-multitouch`.  No extra packages or configuration are needed; Hyprland handles
Wayland touch input natively.

> **Tablet mode / rotation:** The physical screen rotation in tent or tablet mode is
> **not automatic** because the accelerometer (Intel ISH) is broken.  See the
> [Screen Auto-Rotation](#screen-auto-rotation) section below.

### Media Keys and Fn Keys

Two drivers cooperate — but the picture is more nuanced than the driver names suggest:

- **`asus-nb-wmi`** handles keyboard backlight (F4) and exposes `platform-profile` /
  `charge_mode` sysfs controls.  It creates an input device (`event8`, "Asus WMI hotkeys")
  that declares mic mute, volume, and other keycodes but **does not emit events** for them
  on this BIOS version — a firmware limitation.
- **`acpi_video`** intercepts brightness keys (F5/F6) directly via ACPI and adjusts the
  backlight without generating input events.  Screen brightness changes without any
  compositor binding needed.
- **Volume and mute (F1–F3)** arrive on `event0` (the main AT keyboard device) with
  correct keycodes and require explicit Hyprland bindings.

F7 is EC-hardcoded to `Super+P`.  F8–F12 generate no OS events at all.

See **[02-media-keys.md](./02-media-keys.md)** for the full key map, NixOS config changes,
and debugging notes.

---

## Audio

### What Works

Audio is driven by **SOF** (Sound Open Firmware) on the Intel Lunar Lake HD Audio
controller.  The SOF firmware (`intel/sof-ipc4/lnl/sof-lnl.ri` v2.13.0.1) loads
cleanly and brings up the ALSA card `sof-hda-dsp`.  The following all work:

- Headphone jack (3.5 mm combo, jack detection included)
- Internal microphones (2× DMIC, detected from NHLT ACPI tables)
- HDMI / DisplayPort audio output (3 PCM streams)

### ❌ Internal Speakers

The internal speakers are driven by a **Texas Instruments TAS2781** smart amplifier
(`TIAS2781:00` in ACPI, `i2c-TIAS2781:00` in the kernel).  At boot you'll see:

```
tas2781-hda i2c-TIAS2781:00: Get speaker id gpio failed -2
tas2781-hda i2c-TIAS2781:00: Direct firmware load for TAS2XXX10A4.bin failed with error -2
tas2781-hda i2c-TIAS2781:00: tasdevice_prmg_load: Firmware is NULL
```

**Why this happens:**  The `tas2781-hda` driver is designed to support machines where
the same TAS2781 chip is used for either the left or right speaker.  It reads a GPIO
pin defined in the ACPI/DSDT tables to find out which instance this chip is, then
requests a firmware file with that instance number appended — `TAS2XXX10A4**0**.bin`
(instance 0) or `TAS2XXX10A4**1**.bin` (instance 1).

This ASUS machine's ACPI tables do not expose that GPIO descriptor at all, so the read
fails with `-2` (ENOENT — "not found").  The driver then falls back to requesting
`TAS2XXX10A4.bin` with *no* suffix — a filename that does not exist in linux-firmware.
The correctly-named files (`TAS2XXX10A40.bin.zst` and `TAS2XXX10A41.bin.zst`) are
both present in the firmware package; the issue is purely the filename mismatch caused
by the missing GPIO.

**The fix** is to add an extra firmware package that provides a `TAS2XXX10A4.bin.zst`
symlink pointing at the instance-0 variant.  This machine has a single TAS2781, so
instance 0 is correct.

See **[01-speakers-fix.md](./01-speakers-fix.md)** for the full NixOS config and
what to verify afterwards.

---

## WiFi

The **Intel BE201** (Wi-Fi 7 / 802.11be, 320 MHz capable) is driven by `iwlwifi` with
the `iwlmld` firmware op-mode.  The kernel tries to load firmware generation `c99` at
boot, fails, and silently falls back to `c101` — this is normal behaviour and not an
error worth worrying about.  Interface: `wlo1`.

---

## Bluetooth

Bluetooth shares the BE201 radio.  The kernel driver loads and the Intel firmware
(`ibt-0190-0291-iml.sfi` v15-3.26) is fetched at boot.  The hardware is fully ready;
the only thing missing is enabling the service:

```nix
hardware.bluetooth.enable = true;
services.bluetooth.enable = true;
```

---

## NPU — Intel Lunar Lake NPU4

The NPU is exposed as a DRM acceleration device at `/dev/accel/accel0` via the
`intel_vpu` kernel driver.  It loads its firmware (`intel/vpu/vpu_40xx_v1.bin`,
November 2025 build) successfully at boot.  You can verify it's alive:

```bash
ls /dev/accel/        # should show accel0
dmesg | grep intel_vpu
```

### What you can do with it

The NPU is an inference accelerator, not a general-purpose GPU.  It's best suited for
lightweight, sustained, power-efficient AI tasks — the kind of thing you'd otherwise
leave running on the CPU.

**OpenVINO** is the primary way to use it.  OpenVINO is Intel's inference framework
and it has first-class NPU support via the `NPU` device string.  The `openvino` package
is in nixpkgs:

```nix
environment.systemPackages = [ pkgs.openvino ];
```

With OpenVINO you can run ONNX, TensorFlow, and PyTorch models converted to IR format
on the NPU.  The **ONNX Runtime** also supports the NPU via the OpenVINO Execution
Provider — set `providers=["OpenVINOExecutionProvider"]` and point it at `NPU`.

For local LLM inference (ollama, llama.cpp, whisper.cpp) the **Arc 140V GPU** is
more practical today — better framework support, higher throughput for large models.
The NPU shines for smaller, continuously-running tasks like real-time transcription,
wake-word detection, image classification, or on-device translation where you want
inference to be "free" in terms of CPU and battery.

> **Note:** The NPU cannot run arbitrary GPGPU workloads (no OpenCL or Vulkan compute
> on the NPU).  It only runs models compiled specifically for Intel's NPU architecture
> via OpenVINO's model compilation step.

---

## Screen Auto-Rotation

The accelerometer and gyroscope that enable automatic screen rotation in tablet mode
are handled by the **Intel Integrated Sensor Hub** (ISH) at PCI `00:12.0`.  The ISH
is a small co-processor that aggregates sensors and reports them to the OS as IIO
devices.  At boot it tries to load its firmware and fails:

```
intel_ish_ipc 0000:00:12.0: ISH loader: load firmware: intel/ish/ish_lnlm.bin
intel_ish_ipc 0000:00:12.0: ISH loader: cmd 2 failed 10   (×3 with retries)
```

The generic `ish_lnlm.bin.zst` from linux-firmware *is* present and is found by the
kernel — the firmware file isn't missing.  The failure (error code 10, an ISH-internal
status) means the ISH hardware itself is rejecting the firmware binary.  This typically
happens because ISH firmware is often vendor-customised and signed; the linux-firmware
package includes HP, Dell, and Lenovo variants for Lunar Lake but not yet an ASUS
Vivobook variant.

Until ASUS submits their ISH firmware to linux-firmware (or someone extracts it from
a Windows installation), there is no fix available.  Without ISH:

- No accelerometer — screen will not auto-rotate when you flip the lid
- No ambient light sensor
- The hinge angle sensor that switches between laptop/tent/tablet modes may also be
  absent (tablet mode detection may not work)

You can manually force screen rotation in Hyprland with `hyprctl keyword monitor eDP-1, transform, 1`
(or 2, 3 for other orientations) if you need it temporarily.

---

## Webcam

The primary webcam is an **ASUS FHD** unit (USB `3277:0018`) driven by `uvcvideo`.
It appears as `/dev/video0` and `/dev/video1` (the second node is the metadata device).
Works with any V4L2-aware application (OBS, pipewire-camera, cheese, etc.).

The ACPI tables also describe several **OmniVision** sensor devices (`OVTI00AB`,
`OVTI01AF`, `OVTI13B1`) which belong to the Intel IPU6 camera pipeline.  These likely
represent an IR camera for Windows Hello-style face unlock.  The nodes `/dev/video2`
and `/dev/video3` may correspond to these sensors, but the full IPU6 software stack
is not currently configured.  IR face unlock is not feasible on Linux without
significant additional work.

---

## Power Management and ASUS WMI Features

The `asus-nb-wmi` module exposes several useful controls via sysfs:

| Feature | Path | Values |
|---|---|---|
| Performance profile | `/sys/devices/platform/asus-nb-wmi/platform-profile` | `balanced` `low-power` `performance` |
| Battery charge limit | `/sys/devices/platform/asus-nb-wmi/charge_mode` | `0` = full · `1` = balanced · `2` = max lifespan |
| Keyboard backlight | `/sys/class/leds/asus::kbd_backlight/brightness` | `0`–`3` |
| Mic mute LED | `/sys/class/leds/platform::micmute/brightness` | `0` or `1` |

`power-profiles-daemon` will automatically manage `platform-profile` if enabled,
giving you the standard org.freedesktop.UPower power profile D-Bus API that GNOME,
KDE, and Hyprland widgets use.

Fan curve control (`throttle_thermal_policy`) is present in sysfs but the underlying
WMI methods (`0x00110024` / `0x00110025` / `0x00110032`) return ENODEV — they are not
implemented for this model's BIOS.  Fan speed is managed automatically by firmware.

---

## NixOS Config Changes Needed

The current `hosts/flipper/configuration.nix` is missing a few things:

```nix
# Bluetooth — hardware is ready, just needs the service
hardware.bluetooth.enable = true;
services.bluetooth.enable = true;

# Make sure redistributable firmware is on (wifi, bt, sof, vpu all need it)
hardware.enableRedistributableFirmware = true;
```

For the internal speakers fix, see [01-speakers-fix.md](./01-speakers-fix.md).
