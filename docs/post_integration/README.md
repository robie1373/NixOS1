# post_integration — retired source docs

Files here had their knowledge **integrated into the Ledger** (`~/ledger2/`), the single knowledge base.
These are retired originals kept as a reversible audit trail — not a second source of truth. Do not edit or
cite as current. Protocol: `~/ledger2/knowledge-integration.md`.

| Retired source | Integrated into (Ledger) | Date | Quality |
|----------------|--------------------------|------|---------|
| `hyprland/*` | `[[archive-hyprland-flipper]]` → current: `[[nixos-noctalia]]` | 2026-07-08 | superseded |
| `flipper/README.md`, `01-speakers-fix`, `02-media-keys`, `03-disk-encryption`, `04-power-management` | `[[flipper]]` (hardware reference) | 2026-07-15 | superseded |
| `flipper/05-switch-to-kde.md` | `[[nixos-config]]` (DM-switch `boot`+reboot gotcha) — path never taken (flipper=niri) | 2026-07-15 | historical |
| `flipper/1password-wrapper-plan.md`, `1password-safe-rollback.md` | `[[nixos-1password]]` | 2026-07-15 | superseded |
| `flipper/todo.md` | `[[flipper]]` (hardware facts) — silo todo list, non-governing | 2026-07-15 | superseded |
| `comparison/niri-migration-plan.md`, `migration-checklist.md` | `[[nixos-niri]]` | 2026-07-15 | superseded |
| `comparison/module-mapping.md` | `[[nixos-config]]`/`[[nixos-niri]]` (dendritic migration done) | 2026-07-15 | historical |
| `comparison/niri-and-noctalia.md` | `[[nixos-niri]]`/`[[nixos-noctalia]]` (pre-migration research; live now) | 2026-07-15 | historical |
| `archive/multi-host-sharing.md` | `[[nixos-config]]` (HM/mySystem era; module structure) | 2026-07-15 | superseded |
| `observability/build-runbook.md` | `[[visibility-stack]]` | 2026-07-15 | superseded |
| `apps/*` (README, nas-smb, steam-gaming, yazi, mpv, zathura, imv, mpd-ncmpcpp) | `[[nixos-app-stack]]` (synthesized; keybind cheatsheets retired) | 2026-07-15 | superseded |
| `runbooks/add-host`, `add-module`, `debug-build`, `update-system`, `wrap-program` | `[[nixos-config]]` (durable gotchas folded; pre-dendritic structure superseded) | 2026-07-15 | superseded |
| `runbooks/pin-broken-package.md` | `[[nixos-config]]` → "Pinning a broken nixpkgs package" | 2026-07-15 | superseded |
| `runbooks/restic-backup.md` | `[[restic]]` | 2026-07-15 | superseded |
| `migration-checklist.md` | `[[nixos-niri]]` | 2026-07-15 | superseded |
| `sharded-zooming-bonbon.md` | — (stale Hyprland Waybar-widget plan; flipper=niri/noctalia) | 2026-07-15 | superseded |

**Deliberately kept in-repo (NOT retired):** `runbooks/restic-restore.md` — the by-hand, no-AI restore
runbook, kept live in the repo so it survives a bare-metal disaster when the Ledger is unreachable. Its
knowledge is also in `[[restic]]`; the repo copy is a justified redundant break-glass artifact.
