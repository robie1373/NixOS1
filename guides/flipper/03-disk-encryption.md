# Disk Encryption — flipper

**Status as of 2026-03-22:** Disk **is encrypted** (LUKS2). PIN unlock works. YubiKey
FIDO2 path is enrolled but has an OTP interference problem that has not been resolved yet.
Swap is **not encrypted** (known gap — see todo).

---

## Current Partition Layout

```
nvme0n1
├─nvme0n1p1  vfat                /boot   512M
├─nvme0n1p2  swap (unencrypted)          16G
└─nvme0n1p3  LUKS2 → btrfs      /       937G   (subvols: @, @home, @nix)
```

Swap is outside LUKS, meaning hibernate writes full RAM contents (including LUKS keys,
browser sessions) to plaintext disk. This is a known gap — see `guides/flipper/todo.md`.

---

## Current Unlock Configuration

To list all enrolled slots:
```bash
systemd-cryptenroll /dev/nvme0n1p3
```

### Known enrolled slots (as of 2026-03-22)

| Slot | Type | Status |
|---|---|---|
| 0 | password | Recovery passphrase — last resort only, stored in 1Password |
| 1 | tpm2 | **Active daily path** — 6-digit PIN at boot, TPM seals the key |
| 2 | fido2 | Enrolled — OTP disabled 2026-03-22, **pending reboot test** |

> **Note on FIDO2 prompt at boot:** `systemd-cryptsetup` only tries FIDO2 if it detects
> a FIDO2 device at boot time. If the YubiKey 5C is not plugged in, it skips straight to
> the PIN prompt. Not seeing the FIDO2 prompt does not mean FIDO2 was removed from the
> LUKS slots. The FIDO2 enrollment status should be verified with `systemd-cryptenroll`
> before assuming it was wiped.

---

## YubiKey 5C FIDO2 — OTP Interference Problem

### Symptom

When the YubiKey 5C is plugged in at boot, two prompts appear (order depends on how
unlock is attempted):

1. **FIDO2 user presence prompt** — the system asks for a key touch to complete the
   FIDO2 handshake. Touching the key causes the OTP application on the key to fire first,
   emitting a Yubico OTP string (a long `cccccc...` sequence) as keyboard characters to
   the console. The FIDO2 handshake fails / the OTP string corrupts the input. Unlock fails.

2. **PIN/passphrase fallback** — pressing Escape at the FIDO2 prompt (or booting without
   the key connected) falls through to this prompt. Entering the PIN here works correctly.

### Root cause

The YubiKey 5C has multiple USB applications running simultaneously. The OTP application
responds to a capacitive touch by emitting characters over the HID keyboard interface.
This fires at the same time as — or instead of — the FIDO2 user presence event, disrupting
the FIDO2 handshake.

This is unrelated to NixOS issue #329135 (which is a missing `libpcsclite` library in the
initrd). The FIDO2 slot is enrolled and the system reaches out to the key correctly. The
problem is purely the OTP application intercepting the touch.

### Fix

Disable the OTP application on the 5C:
```bash
nix-shell -p yubikey-manager
ykman config usb --disable OTP --force
```

**Impact on other use cases:**

| Use case | Uses OTP slot? | Affected by disabling OTP? |
|---|---|---|
| FIDO2 (websites, disk unlock, SSH keys) | No | Not affected |
| PIV / smart card | No | Not affected |
| OATH TOTP (Yubico Authenticator) | No | Not affected |
| Yubico OTP (`cccccc...` strings) | **Yes** | Disabled |

Yubico OTP is a legacy protocol not used by any of flipper's actual use cases. Disabling
it over USB on the 5C (which has no NFC) disables it completely for this key, with no
practical impact.

### Status

**Done 2026-03-22.** `ykman config usb --disable OTP --force` applied successfully.
Output included a harmless PC/SC warning and a non-fatal "unable to list devices" error
before confirming `USB application configuration updated.` — the `--force` flag bypassed
the preliminary check and the change was applied.

**Next step:** Reboot with 5C plugged in and confirm the FIDO2 prompt appears and touch
unlocks the disk without emitting OTP characters.

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
| YubiKey 5C (fw 5.4.3, S/N 26078339) | ✅ | Full 5-series: FIDO2, PIV, OpenPGP, OATH, CCID. OTP interference issue at boot (see above). |
| YubiKey Bio MPE (USB-C) | ✅ | **Planned purchase.** No OTP slot — fingerprint for FIDO2 UV. |

---

## Unlock Method Options (Reference)

### Option A — Passphrase only

Standard LUKS2 passphrase typed at every boot.

- **Pros:** Simple, no extra hardware dependency, works anywhere
- **Cons:** Full passphrase on every boot, easy to forget if rarely typed
- **Threat coverage:** Drive theft ✅ · Whole-machine theft (off) ✅ · Whole-machine theft (sleeping) ✅

---

### Option B — TPM2 + PIN

The TPM seals the LUKS key against the machine's measured boot state
(firmware, bootloader). A short PIN (not the full passphrase) is required at boot.

- **Pros:** Short PIN instead of long passphrase; hardware brute-force protection; drive
  removed = useless on another machine
- **Cons:** TPM PCR measurements change after BIOS/firmware updates — PIN fails until
  TPM is re-enrolled; whole-machine theft while sleeping stopped only by PIN knowledge
- **Threat coverage:** Drive theft ✅ · Whole-machine theft (off) ✅ · Whole-machine theft (sleeping) ⚠️
- **NixOS:** `boot.initrd.systemd.enable = true` + `systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes`

---

### Option C — FIDO2 / YubiKey 5C

Touch the YubiKey at boot to unlock.

- **Pros:** Physical key required; elegant touch-to-unlock; works on any machine where
  you bring the key
- **Cons:** Lost key = locked out (need recovery slot); key must be present at every boot
- **Threat coverage:** Drive theft ✅ · Whole-machine theft (off) ✅ · Whole-machine theft (sleeping) ✅
- **NixOS:** `systemd-cryptenroll --fido2-device=auto`
- **Current status:** Enrolled but broken due to OTP interference — see above

---

### Option D — YubiKey Bio MPE (planned)

The YubiKey Bio MPE has a fingerprint reader on the key itself. Touch with enrolled
finger instead of bare touch or PIN.

- **Solves three problems at once:**
  1. **LUKS disk unlock** — FIDO2 with fingerprint user verification. Enroll with
     `--fido2-with-user-verification=yes`.
  2. **1Password system unlock** — via `pam_u2f`, 1Password's "unlock with system
     authentication" uses the fingerprint. Eliminates the `op signin` requirement.
  3. **SSH / git auth** — FIDO2 resident SSH keys with biometric user verification.
- **No OTP slot** — the touch-fires-OTP problem does not exist on this key.
- **Fingerprint stored on key, not laptop** — biometric is useless without the physical key.
- **Buy the Multi-Protocol Edition** (not plain Bio) for PIV support. USB-C to match the 5C.

---

## Target Unlock Configuration (at YubiKey Bio purchase)

Three LUKS slots, in priority order:

| Priority | Slot | Method | Scenario |
|---|---|---|---|
| 1 | tpm2 | TPM2 + 6-digit PIN | **Current daily path** — no key needed |
| 2 | fido2 | YubiKey Bio MPE (fingerprint) | Primary key, plug in and touch at boot |
| 3 | fido2 | YubiKey 5C (after OTP disabled) | Backup key — TPM failure, Bio lost/forgotten |
| 4 | password | Recovery passphrase | Last resort; stored in 1Password |

TPM2+PIN stays as the daily no-key-needed path. The Bio replaces bare touch with
fingerprint on the FIDO2 slot. The 5C becomes the second backup once OTP is disabled.

### Why this combination

- Never locked out — three independent paths
- Drive pulled and moved to another machine: useless (no key)
- Whole-laptop theft while powered off: key + fingerprint required
- BIOS update: Bio or passphrase still work; 5C is further backup
- Key lost: other key + passphrase still work

---

## NixOS Implementation Notes

### Required NixOS config

```nix
# Required for systemd-cryptenroll (TPM2 + FIDO2 enrollment)
boot.initrd.systemd.enable = true;

# TPM2 support (if using TPM slot)
security.tpm2.enable = true;
security.tpm2.pkcs11.enable = true;
security.tpm2.tctiEnvironment.enable = true;
```

### Enrollment commands

```bash
# List current slots
systemd-cryptenroll /dev/nvme0n1p3

# Enroll YubiKey Bio MPE with fingerprint UV
systemd-cryptenroll --fido2-device=auto --fido2-with-user-verification=yes /dev/nvme0n1p3

# Enroll YubiKey 5C (after disabling OTP — plain user presence, no PIN)
systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p3

# Wipe and re-enroll a specific slot type
systemd-cryptenroll --wipe-slot=fido2 /dev/nvme0n1p3

# Store recovery passphrase in 1Password before wiping the password slot
```

### Handling BIOS updates (TPM PCR change)

After a firmware update, TPM PCR measurements change and the sealed key won't unseal.
Recovery flow (if TPM slot is enrolled):

1. Boot using YubiKey or recovery passphrase
2. Re-enroll TPM: `systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-with-pin=yes /dev/nvme0n1p3`
3. Normal TPM+PIN boots resume

---

## 1Password Auto-Lock (Related Problem)

1Password reports "your current desktop environment does not support Auto-lock" on
Hyprland because it cannot detect idle time on Wayland. See `hypridle` config for
screen lock — that handles the idle timeout independently.

The `op signin` persistence problem (having to re-run after every reboot) is caused by
1Password's Linux keyring integration attempting to use KWallet (`org.kde.kwalletd5`)
which is not present on this Hyprland setup, and falling back to session-only auth storage.
`gnome-keyring` is running but 1Password does not fall back to it from KWallet — this is
a 1Password Linux bug.

**Resolution path:** YubiKey Bio MPE + `pam_u2f` → enables 1Password system auth via
hardware biometric. This is the cleanest long-term fix and is bundled with the Bio purchase.
