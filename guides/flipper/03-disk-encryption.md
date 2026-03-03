# Disk Encryption — Analysis and Plan

**Status as of 2026-03-03:** Disk is **not encrypted**. This is a known gap
to be resolved at next reinstall via nixos-anywhere.

---

## Current State

The NVMe (WD SN5000S, 1 TB) is partitioned as plain GPT with no LUKS layer:

```
nvme0n1
├─nvme0n1p1  vfat   /boot   512M
├─nvme0n1p2  swap           16G
└─nvme0n1p3  btrfs  /       937G   (subvols: @, @home, @nix)
```

A stolen drive plugs into any machine and everything is readable.
The btrfs subvolume layout is good and will be preserved — adding LUKS is
purely inserting a crypto layer between the partition and btrfs.

---

## Hardware Inventory for Unlock

### Built-in

| Feature | Status | Notes |
|---|---|---|
| TPM 2.0 | ✅ Present | Intel PTT (firmware TPM), `/dev/tpm0`, `/dev/tpmrm0`, driver `tpm_crb` |
| Fingerprint reader | ❌ Absent | Not present on this SKU |
| IR face unlock | ❌ Not feasible | IPU6 camera pipeline not configured on Linux |

### YubiKeys on hand

| Key | FIDO2 | Notes |
|---|---|---|
| FIDO U2F Security Key (fw 4.1.8) | ❌ | U2F only — too old, no FIDO2 |
| YubiKey 5C (fw 5.4.3, S/N 26078339) | ✅ | Full 5-series: FIDO2, PIV, OpenPGP, OATH, CCID |

The YubiKey 5C is USB-C and supports everything needed. The old Security
Key cannot be used for FIDO2 disk unlock but still works for FIDO U2F
(website 2FA).

Note: `ykman` emits a PC/SC warning about CCID when `pcscd` is not running.
This is harmless for FIDO2 disk unlock — FIDO2 uses HID, not smart card
protocol.

---

## Unlock Method Options

### Option A — Passphrase only

Standard LUKS2 passphrase typed at every boot.

- **Pros:** Simple, no extra hardware dependency, works anywhere
- **Cons:** Full passphrase on every boot, easy to forget if rarely typed
- **Threat coverage:** Drive theft ✅ · Whole-machine theft (off) ✅ · Whole-machine theft (sleeping) ✅

---

### Option B — TPM2 + PIN

The TPM seals the LUKS key against the machine's measured boot state
(firmware, bootloader). A short PIN (not the full passphrase) is required
at boot. The key never leaves the TPM chip.

- **Pros:** Short PIN instead of long passphrase; hardware brute-force
  protection; if drive is removed it can't decrypt on another machine
- **Cons:** TPM PCR measurements change after BIOS/firmware updates —
  the PIN will fail until the TPM is re-enrolled (see recovery slot below);
  whole-machine theft while sleeping = attacker can boot and is only stopped
  by the PIN
- **Threat coverage:** Drive theft ✅ · Whole-machine theft (off) ✅ ·
  Whole-machine theft (sleeping) ⚠️ (stopped only by PIN knowledge)
- **NixOS:** `boot.initrd.systemd.enable = true` +
  `systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes`

---

### Option C — FIDO2 / YubiKey 5C

Touch the YubiKey at boot to unlock. The LUKS slot holds a FIDO2 credential
bound to the specific key.

- **Pros:** Physical key required; elegant touch-to-unlock; works on any
  machine where you bring the key
- **Cons:** Lost key = locked out (need recovery slot); key must be with
  you at every boot
- **Threat coverage:** Drive theft ✅ · Whole-machine theft (off) ✅ ·
  Whole-machine theft (sleeping) ✅ (attacker also needs the physical key)
- **NixOS:** `systemd-cryptenroll --fido2-device=auto`

---

### Option D — YubiKey Bio Multi-Protocol Edition (future purchase)

The YubiKey Bio MPE has a fingerprint reader on the key itself. Instead of
a PIN or bare touch, you touch the key with an enrolled finger.

**This solves three problems at once for this machine:**

1. **LUKS disk unlock** — FIDO2 with fingerprint user verification instead
   of a PIN. Same security as YubiKey 5C FIDO2, but ergonomically better.
2. **1Password system unlock** — via `pam_u2f`, NixOS can use the YubiKey
   Bio as a PAM authentication factor, enabling 1Password's "unlock with
   system authentication." This eliminates the `op signin` requirement on
   every boot (the long-running pain on this machine).
3. **SSH / git auth** — FIDO2 resident SSH keys with biometric user
   verification.

The fingerprint template is stored on the key, not the laptop. This is a
security feature — the biometric is useless without the physical key.

**Buy the Multi-Protocol Edition** (not the plain Bio). The MPE adds PIV
and is worth the small price premium. Get the USB-C form factor to match
the YubiKey 5C already in use.

---

## Recommended Setup (at reinstall)

Three LUKS unlock slots, in priority order:

| Slot | Method | Scenario |
|---|---|---|
| 1 | TPM2 + PIN | Every normal boot — short PIN, no key needed |
| 2 | YubiKey 5C FIDO2 | TPM fails after BIOS update; or when carrying the key |
| 3 | Recovery passphrase | Last resort; store in 1Password |

**If YubiKey Bio MPE is purchased before reinstall:**
Replace slot 1 with YubiKey Bio FIDO2 (fingerprint) and keep TPM2+PIN as
slot 2. This gives fingerprint-at-boot as the primary flow.

### Why this combination

- Never locked out — three independent paths to decryption
- Drive pulled and moved to another machine: useless (no TPM, no YubiKey)
- Whole-laptop theft while powered off: PIN or YubiKey required
- BIOS update breaks TPM PCR: fall back to YubiKey or passphrase, then
  re-enroll TPM
- YubiKey lost: TPM+PIN and passphrase still work

---

## NixOS Implementation Notes

### disko change

The btrfs subvolume layout is unchanged. Add a `luks` layer between the
partition and btrfs in `hosts/flipper/disko.nix`:

```nix
root = {
  size = "100%";
  content = {
    type = "luks";
    name = "cryptroot";
    settings = {
      allowDiscards = true;   # SSD TRIM — safe for NVMe
    };
    content = {
      type = "btrfs";
      extraArgs = [ "-L" "nixos" "-f" ];
      subvolumes = {
        "@"     = { mountpoint = "/";     mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ]; };
        "@home" = { mountpoint = "/home"; mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ]; };
        "@nix"  = { mountpoint = "/nix";  mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ]; };
      };
    };
  };
};
```

### NixOS config additions

```nix
# Required for systemd-cryptenroll (TPM2 + FIDO2 enrollment)
boot.initrd.systemd.enable = true;

# TPM2 support
security.tpm2.enable = true;
security.tpm2.pkcs11.enable = true;
security.tpm2.tctiEnvironment.enable = true;
```

### Post-install enrollment (run after nixos-anywhere completes)

```bash
# Enroll TPM2 with PIN (slot auto-assigned)
systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes /dev/nvme0n1p3

# Enroll YubiKey 5C FIDO2 (plug in key first)
systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p3

# The recovery passphrase was set during install — store it in 1Password
# Verify all slots:
systemd-cryptenroll /dev/nvme0n1p3
```

### Handling BIOS updates (TPM PCR change)

After a firmware update, the TPM PCR measurements change and the sealed
key won't unseal. Recovery flow:

1. Boot using YubiKey or recovery passphrase
2. Re-enroll TPM: `systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-with-pin=yes /dev/nvme0n1p3`
3. Normal TPM+PIN boots resume

---

## 1Password Auto-Lock (Related Problem)

1Password reports "your current desktop environment does not support
Auto-lock" on Hyprland because it cannot detect idle time on Wayland.
This is a separate issue from disk encryption but intersects with it:

- **Without disk encryption + without auto-lock:** stolen laptop = full access
- **With disk encryption:** stolen laptop requires PIN/key to decrypt, regardless
  of 1Password's auto-lock state

The `op signin` persistence problem (having to re-run after every reboot)
is caused by 1Password's Linux keyring integration attempting to use
KWallet (`org.kde.kwalletd5`) which is not present on this Hyprland setup,
and falling back to session-only auth storage.

**Workarounds in priority order:**

1. **YubiKey Bio MPE + `pam_u2f`** — enables 1Password system auth via
   hardware biometric; cleanest long-term fix
2. **Standalone `op` CLI session** — disable "Integrate with 1Password CLI"
   in app settings; use `op signin` once per 30-day session; session stored
   in `~/.config/op/` (protected by disk encryption once that's in place)
3. **Accept the workflow** — unlock 1Password app + `op signin` once per
   login session; two steps, both fast

Status: gnome-keyring is running and on D-Bus (`org.freedesktop.secrets`)
but 1Password does not fall back to it from KWallet. This is a 1Password
Linux bug.

---

## Reinstall Plan (Overview)

See the nixos-anywhere docs for full procedure. High-level:

1. Boot flipper from NixOS USB or netboot
2. From the VM on the other machine (or over SSH):
   `nixos-anywhere --flake .#flipper root@<flipper-ip>`
3. nixos-anywhere runs disko (which will now create the LUKS partition),
   installs NixOS, and reboots
4. After first boot: enroll TPM2+PIN and YubiKey FIDO2 with
   `systemd-cryptenroll`
5. Store recovery passphrase in 1Password
6. Push updated disko.nix to git before reinstalling
