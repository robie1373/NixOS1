# Guide 01: Fixing Internal Speakers (TAS2781)

The internal speakers on the ASUS Vivobook 14 Flip TP3407SA require two fixes:

1. **Firmware filename fix** — the kernel driver requests a firmware file that
   doesn't exist under that name
2. **Amplifier register fix** — the driver loads firmware but doesn't properly
   configure the TAS2781 amplifier registers, resulting in nearly silent output

Both are implemented as NixOS modules. The firmware fix lives in
`hosts/flipper/configuration.nix` and the register fix is in
`modules/system/speaker-fix.nix`.

---

## Problem 1: Missing Firmware Filename

The TAS2781 is a smart amplifier. The driver identifies which instance it's
talking to by reading a GPIO pin from the ACPI tables, then appends an instance
number to the firmware filename:

```
instance = 0  →  requests TAS2XXX10A4 0 .bin
instance = 1  →  requests TAS2XXX10A4 1 .bin
```

This ASUS Vivobook has **one** TAS2781. Its ACPI tables don't define the
speaker-ID GPIO at all:

```
tas2781-hda i2c-TIAS2781:00: Get speaker id gpio failed -2
```

With no instance number, the driver falls back to `TAS2XXX10A4.bin` — which
doesn't exist. The linux-firmware package only ships the suffixed variants
(`TAS2XXX10A40.bin` and `TAS2XXX10A41.bin`).

### Fix

Copy the instance-0 firmware under the unsuffixed name. In
`hosts/flipper/configuration.nix`:

```nix
hardware.firmware = [
  (pkgs.runCommand "tas2781-firmware-fix" {} ''
    mkdir -p $out/lib/firmware
    cp ${pkgs.linux-firmware}/lib/firmware/TAS2XXX10A40.bin \
       $out/lib/firmware/TAS2XXX10A4.bin
  '')
];
```

We use `cp` rather than `ln -s` because NixOS compresses firmware with zstd
during the build. A symlink would have `.zst` appended to both its name and
target path, breaking it when the target isn't zstd-compressed.

---

## Problem 2: Amplifier Registers Not Configured

Even with firmware loaded, the speakers produce only very faint sound. The
`tas2781-hda` driver doesn't properly power on the amplifiers for this ASUS
model. The amplifiers are at addresses `0x38` and `0x3d` on i2c bus 0.

The fix writes the correct register values over i2c after PipeWire has opened
the ALSA device. This is critical — writing the registers too early is useless
because PipeWire re-initializes the device and resets them.

### Fix

`modules/system/speaker-fix.nix` provides `mySystem.speakerFix.enable`. It
creates a systemd service (`fix-speakers.service`) that:

1. Waits for the `pipewire` process to appear (polls for up to 30 seconds)
2. Sleeps 2 more seconds for PipeWire to open the ALSA sink
3. Writes amplifier configuration registers via `i2cset` to both TAS2781
   instances

The service runs after `graphical.target` and also on resume from sleep
(`sleep.target`).

Enable it in `hosts/flipper/configuration.nix`:

```nix
mySystem.speakerFix.enable = true;
```

### Hardware-Specific Values

These were determined by probing this specific machine:

| Parameter      | Value                | How to verify                                      |
|----------------|----------------------|----------------------------------------------------|
| i2c bus        | `0`                  | `readlink -f /sys/bus/i2c/devices/i2c-TIAS2781:00` |
| Amp addresses  | `0x3d`, `0x38`       | `sudo i2cdetect -r 0` (with `i2c-dev` loaded)      |
| Kernel module  | `i2c-dev`            | Loaded automatically via `boot.kernelModules`       |

If the i2c bus number or addresses change (e.g. after a major kernel update),
update the values in `modules/system/speaker-fix.nix`.

### Boot Delay

The service shows a "start job running" message on the login screen while it
waits for PipeWire (~25 seconds). This is cosmetic and does not block login.

---

## Verifying Both Fixes

After `nixos-rebuild switch` and reboot:

```bash
# Firmware loaded — should see "bound" with no firmware errors
sudo dmesg | grep -i tas2781

# Service ran successfully
systemctl status fix-speakers

# Speakers should be loud — play a test tone
nix shell nixpkgs#alsa-utils -c speaker-test -t wav -c 2
```

If speakers are quiet after reboot, re-run the service manually:

```bash
sudo systemctl restart fix-speakers
```

If that fixes it, the timing is off — increase the sleep in the script.

---

## Manual Testing

To test the i2c fix without rebooting:

```bash
nix shell nixpkgs#i2c-tools -c sudo bash /tmp/fix-speakers.sh
```

(The `/tmp/fix-speakers.sh` script from initial debugging uses the same
register values as the systemd service.)

---

## Why This Workaround?

The right long-term fix is a kernel patch that properly configures the TAS2781
amplifier registers during driver probe. The register-write workaround and the
firmware filename fix are both needed until upstream support improves.

Reference: https://gist.github.com/rraks/4edddb99b50b94fe6298adbf3c9f43eb

---

## If Speakers Stop Working After a Kernel Update

1. Check if the i2c bus number changed: `readlink -f /sys/bus/i2c/devices/i2c-TIAS2781:00`
2. Check if the amplifier addresses changed: `sudo modprobe i2c-dev && nix shell nixpkgs#i2c-tools -c sudo i2cdetect -r <bus>`
3. Check if the firmware filename convention changed: `sudo dmesg | grep -i tas2781`
4. Update `modules/system/speaker-fix.nix` and/or the firmware `cp` accordingly
