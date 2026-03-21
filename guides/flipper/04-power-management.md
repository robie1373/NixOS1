# flipper — Power Management

**Goal:** Close the lid or let the battery die and resume exactly where you left off.

---

## How It Works: Hibernate vs Suspend vs Hybrid-Sleep

| Mode | What happens | Resume speed | Survives power loss |
|---|---|---|---|
| Suspend | RAM stays powered, CPU halted | ~1 second | No |
| Hibernate | RAM written to swap, machine off | ~15–30 seconds (reads swap) | Yes |
| Hybrid-sleep | RAM written to swap AND CPU halted | ~1 second (from RAM) | Yes (falls back to swap) |

**This config uses hybrid-sleep** everywhere except critical battery (which uses plain hibernate). Hybrid-sleep gives you fast resume when power survived the sleep, and safe recovery from swap if the battery died while you were away.

---

## What Was Configured

### `hosts/flipper/configuration.nix`

```nix
boot.resumeDevice = "/dev/disk/by-partlabel/disk-main-swap";

services.logind.lidSwitch              = "hybrid-sleep";
services.logind.lidSwitchExternalPower = "hybrid-sleep";

services.upower.enable              = true;
services.upower.criticalPowerAction = "Hibernate";
```

- `boot.resumeDevice` — tells the kernel which partition holds the hibernate image. The label `disk-main-swap` is set by disko (disk name "main" + partition "swap").
- `lidSwitch` / `lidSwitchExternalPower` — what logind does when the lid closes, on battery and on AC respectively.
- `criticalPowerAction = "Hibernate"` — at critical battery, UPower triggers a plain hibernate (no RAM retention — we don't trust RAM at near-zero power).

### `modules/home/desktop-hyprland.nix`

The hypridle idle listener was changed from `systemctl suspend` to `systemctl hybrid-sleep`. After 15 minutes of idle, the machine hybrid-sleeps.

---

## Prerequisites Already in Place

- **16G swap partition** — matches RAM, required for hibernate. Confirmed in `disko.nix`.
- **`boot.initrd.systemd.enable = true`** — systemd initrd handles the resume path automatically.
- **`boot.resumeDevice`** — already set; NixOS passes `resume=` to the kernel automatically.

---

## Testing

Test manually before relying on lid close:

```bash
# Test hybrid-sleep
systemctl hybrid-sleep
# Machine powers down. Open the lid / press power. Session should return exactly as left.

# Test hibernate (critical battery path)
systemctl hibernate
# Slower resume — reads from swap instead of RAM.

# Verify swap is active and large enough
swapon --show
# Should show /dev/nvme0n1p2 (or by-partlabel path), size ~16G

# Check resume device kernel parameter was set
cat /proc/cmdline | tr ' ' '\n' | grep resume
# Should show: resume=/dev/disk/by-partlabel/disk-main-swap
```

---

## Known Issue: Unencrypted Swap

The swap partition lives **outside** the LUKS container (it's a sibling partition, not inside `cryptroot`). This means:

- Hibernate writes the full RAM image — including the LUKS master key, browser sessions, open documents — to **plaintext disk**.
- An attacker with physical access and a screwdriver *while the machine is hibernated* could read sensitive data from the swap partition.
- Once the machine is awake and running, there is no additional risk beyond normal operation.

**Is this a real threat?** For a typical laptop threat model (theft, not targeted attack), the window is narrow: the attacker would need to disassemble the laptop and image the NVMe before you wake it up. Disk encryption still protects against power-off theft.

**Mitigations:**

1. **Accept the tradeoff** (current state) — reasonable for most use cases.

2. **Encrypt swap with a fixed key** — complex. Requires:
   - Creating a LUKS-encrypted swap device with a key stored in the initrd
   - That key must be available before `boot.resumeDevice` is read, which means it can't be protected by the same TPM2/FIDO2 unlock that protects the root partition
   - The key would typically be stored unencrypted in the initrd (still better than plaintext swap, since initrd is inside the encrypted root)
   - This is non-trivial to set up correctly with systemd initrd — design carefully before implementing
   - See the todo list for tracking

3. **Use `hybrid-sleep` with a short timeout and accept some exposure** — already the current approach; the machine transitions from RAM (exposed) to disk (also exposed) but the total window is bounded by your idle timeout.

---

## Future: Session Restore on Reboot

Hibernate covers the "close lid" and "battery dies" cases. The remaining gap is deliberate reboot/shutdown — currently you lose all window state.

**Plan (not yet implemented):** A pre-shutdown systemd unit that runs:
```bash
hyprctl clients -j > ~/.local/share/hypr/last-session.json
```

Then a startup script that reads `last-session.json` and relaunches apps on the correct workspaces. This restores *layout* (which apps, which workspaces, window sizes) but not internal state (open files, browser tabs, etc.).

**App-specific state that already works:**
- Firefox — full session restore built-in (tabs, scroll position, form data)
- Terminal — use `tmux` or `zellij` with session persistence; auto-attach on terminal open

See the todo list for tracking this work.

---

## Logind Reference

Other `lidSwitch` values if you want to change behaviour later:

| Value | Behaviour |
|---|---|
| `ignore` | Do nothing |
| `poweroff` | Shut down |
| `suspend` | Suspend to RAM (fast, loses state on power loss) |
| `hibernate` | Suspend to disk (slow resume, safe) |
| `hybrid-sleep` | Both (fast resume, safe) — current setting |
| `suspend-then-hibernate` | Suspend first, hibernate after a delay |

`suspend-then-hibernate` is another option: stays in RAM for N minutes (fast resume), then writes to disk and powers off. Controlled by `systemd-sleep.conf`'s `HibernateDelaySec`. Useful if you want near-instant resume for short naps but full protection for overnight.
