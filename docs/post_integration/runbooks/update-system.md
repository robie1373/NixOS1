# Runbook: Update the System

---

## Routine update (all inputs)

```bash
cd ~/nixos-config
nix flake update                          # advance flake.lock to latest nixpkgs, HM, etc.
build                                     # → nixos-rebuild build --flake .#<hostname>
```

Build first. Fix any errors before activating. See `docs/runbooks/debug-build.md`.

```bash
rebuild                                   # → sudo nixos-rebuild switch --flake .#<hostname>
git add flake.lock && git commit -m "Update flake inputs $(date +%Y-%m-%d)"
```

---

## Full switch to activate

```bash
nh os switch ~/nixos-config/    # `nh os switch .` if already in nixos-config. 
                                # probably wise to reboot after this. new kernels 
                                # and some packages are only activated after reboot
```

---

## Selective update (single input)

```bash
nix flake update nixpkgs                  # update only nixpkgs, leave other inputs pinned
nix flake update home-manager             # update only home-manager
```

---

## After a firmware / BIOS update (flipper)

TPM PCR measurements change after firmware updates. The TPM2+PIN slot will fail to unseal until re-enrolled. Recovery path:

1. Boot using YubiKey or recovery passphrase
2. Re-enroll TPM:
   ```bash
   systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-with-pin=yes /dev/nvme0n1p3
   ```
3. Normal TPM+PIN boots resume

Full disk encryption context: `docs/flipper/03-disk-encryption.md`

---

## Rolling back

```bash
sudo nixos-rollback                       # activate previous generation
```

Or to a specific generation:

```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
sudo nixos-rebuild switch --flake .#<hostname> --rollback
```

To revert the lock file:

```bash
git checkout flake.lock
rebuild
```

If the build itself was broken (not just the lock file), see `docs/runbooks/debug-build.md` → Step 5.

---

## A package is broken after update

Pin the broken package to a known-good version while nixpkgs catches up.

See `docs/runbooks/pin-broken-package.md` for the full strategy and a worked example.
