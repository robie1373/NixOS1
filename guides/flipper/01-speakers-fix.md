# Guide 01: Fixing Internal Speakers (TAS2781)

The internal speakers are silent because the `tas2781-hda` kernel driver requests a
firmware file named `TAS2XXX10A4.bin` — a name that doesn't exist.  The correct files
(`TAS2XXX10A40.bin` and `TAS2XXX10A41.bin`) are present in linux-firmware; the driver
just can't figure out which one to ask for.  This guide explains exactly why and shows
the one-block NixOS fix.

---

## What the Driver Is Trying to Do

The TAS2781 is a smart amplifier used across many laptop models.  Machines often have
two of them — one per speaker channel.  The driver identifies which instance it's
talking to by reading a GPIO pin described in the ACPI/DSDT tables, then appends that
instance number to the firmware filename before requesting it:

```
instance = 0  →  requests TAS2XXX10A4 0 .bin
instance = 1  →  requests TAS2XXX10A4 1 .bin
```

This ASUS Vivobook has **one** TAS2781.  Its ACPI tables simply don't define the
speaker-ID GPIO at all.  When the driver tries to read it:

```
tas2781-hda i2c-TIAS2781:00: Get speaker id gpio failed -2
```

`-2` is `ENOENT` — the GPIO descriptor doesn't exist in the ACPI namespace.  With no
instance number to work with, the driver falls back to requesting the base name with
no suffix:

```
tas2781-hda i2c-TIAS2781:00: Direct firmware load for TAS2XXX10A4.bin failed with error -2
```

That file also doesn't exist.  The linux-firmware package only ships the suffixed
variants, because for multi-speaker machines that's always what gets requested.

---

## The Fix

Create an extra firmware package that provides the missing filename as a copy of
the instance-0 variant.  Add this to `hosts/flipper/configuration.nix`:

```nix
{ config, pkgs, ... }:

{
  # ... existing config ...

  hardware.firmware = [
    (pkgs.runCommand "tas2781-firmware-fix" {} ''
      mkdir -p $out/lib/firmware
      cp ${pkgs.linux-firmware}/lib/firmware/TAS2XXX10A40.bin \
         $out/lib/firmware/TAS2XXX10A4.bin
    '')
  ];
}
```

`hardware.firmware` appends extra paths to the firmware search order.  The kernel's
firmware loader checks all registered paths in sequence, so it will find
`TAS2XXX10A4.bin` in our extra package.

We use `cp` rather than `ln -s` because NixOS compresses firmware with zstd during
the build.  A symlink would have `.zst` appended to both its name and target path,
breaking it when the target isn't zstd-compressed.  Copying the file lets the
compression step work on a real file.

The copy is of instance 0 (`TAS2XXX10A40.bin`) because this machine has a single
TAS2781 and instance 0 is the conventional default.

---

## Verifying the Fix

After `nixos-rebuild switch`, reboot (the firmware is loaded during driver probe at
boot, not on-demand):

```bash
# No more TAS2781 errors
dmesg | grep -i tas2781

# Should see the amplifier bound successfully:
#   snd_hda_codec_alc269: bound i2c-TIAS2781:00 (ops tas2781_hda_comp_ops [...])

# Check that a speaker output exists in PipeWire
pactl list sinks | grep -A5 "Name:"

# Quick test — play something through the internal speakers
speaker-test -t wav -c 2
```

If you still see `Firmware is NULL` after the reboot, double-check that the file
exists on the booted system:

```bash
ls -la /run/current-system/firmware/TAS2XXX10A4.bin*
```

> **If speakers are silent but no driver errors appear:** The TAS2781 firmware loaded
> but the SOF topology may not have routed audio to it.  Check `alsamixer` to make
> sure the speaker output isn't muted, and look at `pactl list cards` to confirm the
> `sof-hda-dsp` card shows speaker ports.  The headphone jack should work regardless
> of the TAS2781 status.

---

## Why Not Just Patch the Kernel?

The right long-term fix is a kernel patch that handles the missing GPIO more gracefully
— either by defaulting to instance 0 when the GPIO read fails, or by looking up the
instance through an alternate ACPI method.  That patch has been discussed upstream but
hasn't landed yet as of kernel 6.18.

The firmware copy workaround achieves the same result without touching the kernel
and is easy to remove once the upstream fix arrives.
