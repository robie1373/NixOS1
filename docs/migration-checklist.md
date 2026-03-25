# Dry Dock Migration Checklist

Living document. Check items off as completed.
Last updated: 2026-03-24.

Reference: `docs/comparison/niri-migration-plan.md` for rationale.
Reference: `github.com/vimjoyer/nixconf` for pattern examples.

---

## Pre-flight: Outstanding Small Fixes

These are known issues to clear before starting the migration. Small, isolated, low-risk.

- [x] **Fix foot `colors-dark` deprecation warning** ✓ (already done, found at line 701)

- [x] **Investigate Claude SSH key 1Password prompt** ✓ 2026-03-24
  - Cause: git remote is SSH; Claude Code checks remote on startup; hits 1Password agent
  - Resolution: expected behavior — approve the prompt once per login session, not spurious

---

## Phase 0: Quick Wins

Independent of the migration. Can be done now, in any order.

### `nh` — Better rebuild UX
- [x] `programs.nh.enable = true` + `flake = "/home/robie/nixos-config"` in `modules/system/common.nix`
- [x] Tested — working ✓
- [x] Shell aliases updated: `rebuild`/`build`/`ntest` now use `nh os switch/build/test`

### `comma` + `nix-index-database`
- [x] Added `nix-index-database` flake input to `flake.nix`
- [x] Added `hmModules.nix-index` import to both hosts in `parts/nixos.nix`
- [x] `programs.nix-index-database.comma.enable = true` + `programs.nix-index.enable = true` in `modules/home/common.nix`
- [x] Tested — working ✓

### `wlr-which-key` — Visual keybind cheatsheet
- [x] Added `wlr-which-key` to `home.packages` in `modules/home/desktop-hyprland.nix`
- [x] Config written to `xdg.configFile."wlr-which-key/config.yaml"` with Catppuccin Macchiato theme
- [x] Bound `Super+/` in Hyprland keybinds
- [x] Tested — working ✓

---

## Phase 1: Dendritic + Wrapper-Modules Migration

**Goal:** Restructure the entire config to match vimjoyer's pattern.
Each feature = one file = one derivation. Home-manager retained only for 1Password.

### 1.1 — Study and Prepare

- [x] **Read vimjoyer's nixconf thoroughly** ✓ 2026-03-25
  - `import-tree` wiring understood — entire `./modules` tree is auto-merged, no registration
  - `nix-wrapper-modules` API understood — each program is a wrapped derivation with embedded config
  - Module mapping documented in `docs/comparison/module-mapping.md`
- [x] **Document the mapping** ✓ 2026-03-25 — `docs/comparison/module-mapping.md`
- [x] **Cachix decision** ✓ — vimjoyer uses no custom cache; no cachix needed for wrapper-modules

**Decisions recorded (2026-03-25):**
- Drop `mySystem.*` / `myHome.*` enable flags — import-based toggles in migrated modules
- Keep home-manager through Phase 1; eliminate in Phase 2 alongside 1Password
- `hjem` not on roadmap; kept in mind as fallback only
- `modules/theme.nix` (Catppuccin Macchiato palette as `self.theme`) is the first thing built in Phase 1, before any module work
- 1Password is Phase 2 — mechanical plumbing, planning doc before implementation

### 1.2 — New Flake Inputs + Theme

- [ ] Create branch: `git checkout -b refactor/dendritic`
- [ ] Add `import-tree` input to `flake.nix`:
  ```
  import-tree.url = "github:vic/import-tree";
  ```
- [ ] Add `nix-wrapper-modules` input:
  ```
  nix-wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";
  ```
- [ ] `nix flake update` to pull new inputs
- [ ] Verify `flake.lock` updated cleanly: `nix flake check`
- [ ] **Create `modules/theme.nix`** — Catppuccin Macchiato palette as `self.theme` flake output
  - All hex values in one place; every wrapper imports `self.theme` rather than hardcoding colors
  - Wire as `flake.theme = { ... }` in the flake-parts module
  - Verify `nix eval .#theme` returns the palette

### 1.3 — Restructure `flake.nix`

- [ ] Rewrite `flake.nix` to use `import-tree`:
  ```nix
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
    (inputs.import-tree ./modules);
  ```
- [ ] Verify the flake evaluates: `nix flake show`
- [ ] Keep `parts/nixos.nix` intact until new host modules are ready (do not delete yet)

### 1.4 — Create New Module Directory Structure

- [ ] Create `modules/hosts/` directory
- [ ] Create `modules/features/` directory (or mirror vimjoyer's layout exactly)
- [ ] Create `modules/programs/` directory for wrapper-module derivations
- [ ] Do NOT delete any existing files yet — new and old coexist during migration

### 1.5 — Migrate Host Definitions

- [ ] Create `modules/hosts/flipper/default.nix`
  - Imports list of feature modules for flipper
  - Sets `networking.hostName`, `system.stateVersion`
  - Replaces role of `hosts/flipper/configuration.nix` + `parts/nixos.nix` flipper entry
- [ ] Create `modules/hosts/nixos1/default.nix`
  - Mirrors above for the VM
- [ ] Update `flake.nix` (or let import-tree discover) host definitions
- [ ] Verify both hosts build: `nixos-rebuild build --flake .#flipper`

### 1.6 — Migrate System Feature Modules

Migrate each module from `modules/system/` to dendritic files. Do one at a time, build-test after each.

- [ ] `common.nix` → `modules/features/common/default.nix`
  - boot, networking, locale, users, git, neovim, tailscale
- [ ] `audio.nix` → `modules/features/audio/default.nix`
- [ ] `vm-guest.nix` → `modules/features/vm-guest/default.nix`
- [ ] `1password.nix` (system side) → `modules/features/1password/default.nix`
  - System packages, polkit rule
  - Keep home-manager 1password.nix alive separately (SSH agent, systemd services)
- [ ] `desktop-hyprland.nix` (system side) → `modules/features/desktop-hyprland/default.nix`
  - Hyprland enable, portals, fonts, greetd, env vars
  - Home-manager program configs move to wrapper-modules (see 1.7)
- [ ] `desktop-kde.nix` → `modules/features/desktop-kde/default.nix` (low priority, not used on flipper)

### 1.7 — Migrate Home Programs to Wrapper-Modules

Each program becomes a wrapped derivation. Follow vimjoyer's `modules/wrappedPrograms/` pattern exactly.

- [ ] **kitty** → `modules/programs/kitty/default.nix`
  - Font, theme, keybinds, Catppuccin Macchiato
- [ ] **fish** → `modules/programs/fish/default.nix`
  - Shell aliases, abbreviations, prompt
- [ ] **waybar** → `modules/programs/waybar/default.nix`
  - Full config + CSS, all custom modules (iphone, etc.)
  - niri/workspaces module can be added later in Phase 3
- [ ] **rofi** → `modules/programs/rofi/default.nix`
  - Catppuccin theme
- [ ] **dunst** → `modules/programs/dunst/default.nix`
- [ ] **hyprpaper** → `modules/programs/hyprpaper/default.nix`
- [ ] **hypridle** → `modules/programs/hypridle/default.nix`
- [ ] **hyprlock** → `modules/programs/hyprlock/default.nix`
- [ ] **kitty (foot on VMs)** — foot stays on nixos1; confirm foot config is handled

### 1.8 — Migrate Remaining Home Modules

Small home modules that are currently HM-only but aren't program wrappers.

- [ ] `home/claude.nix` → fold into `modules/features/claude/default.nix`
  - `programs.claude-code.enable` — check if this can be a system package instead
- [ ] `home/gemini-cli.nix` → `modules/features/gemini-cli/default.nix`
- [ ] `home/obsidian.nix` → `modules/features/obsidian/default.nix` or system package
- [ ] `home/common.nix` remaining pieces (git config, home packages not yet wrapped)

### 1.9 — 1Password Home Services (Keep Alive in HM)

- [ ] Confirm `modules/home/1password.nix` still loads correctly after restructure
  - SSH agent socket
  - `matchBlocks` SSH config
  - `systemd.user.services.onepassword-gui`
- [ ] Confirm `op item get` still works after rebuild
- [ ] Confirm SSH agent still used by git/GitHub

### 1.10 — Drop ifuse

- [ ] Remove `systemd.user.services.ifuse-mount` and `ifuse-unmount` from home config
- [ ] Remove udev rules for iPhone auto-mount from `hosts/flipper/configuration.nix`
- [ ] Remove `custom/iphone` waybar module (or leave it, it's low cost)
- [ ] Keep `mount-phone` alias in fish (it's a one-liner, trivial to keep)
- [ ] Keep `ifuse` and `libimobiledevice` in system packages (they're small)

### 1.11 — Remove Old Structure

Only after all modules are migrated and the config builds and boots cleanly.

- [ ] `nixos-rebuild switch --flake .#flipper` on flipper — confirm everything works
- [ ] Boot and test: Hyprland launches, kitty works, waybar correct, 1Password agent active
- [ ] Test `op item get` and SSH to GitHub
- [ ] Delete `modules/system/` directory
- [ ] Delete `modules/home/` directory (except `home/1password.nix` — keep until Phase 2)
- [ ] Delete `parts/` directory
- [ ] Delete `hosts/flipper/configuration.nix` and `hosts/flipper/home.nix` (replaced by `modules/hosts/flipper/`)
- [ ] `git commit` — migration complete
- [ ] `git checkout main && git merge refactor/dendritic`

---

## Phase 2: Eliminate Home-Manager

**Goal:** Remove the last home-manager dependency (1Password). Then remove HM from the flake entirely.

- [ ] **Research:** How does vimjoyer (or the community) handle 1Password GUI + CLI without HM?
  - Specifically: `systemd.user.services` for the GUI daemon
  - SSH agent socket configuration without `programs.ssh.matchBlocks`
  - Evaluate: can `systemd.user.services` be declared at system level scoped to a user?
    (`systemd.user.services` IS valid in NixOS system config — verify this works for the daemon)
- [ ] **Document findings** in `docs/flipper/1password-wrapper-plan.md` before implementing
- [ ] Create `modules/programs/1password/default.nix` as a wrapper-module derivation
- [ ] Migrate SSH agent socket config out of HM (system-level or wrapper)
- [ ] Migrate `systemd.user.services.onepassword-gui` to system-level `systemd.user.services`
- [ ] Rebuild and test: `op item get`, SSH to GitHub, 1Password GUI, CLI integration
- [ ] Remove `home-manager` input from `flake.nix`
- [ ] Remove all remaining HM references
- [ ] `nix flake update` — confirm HM is gone from `flake.lock`
- [ ] Final rebuild and full test of 1Password workflow

---

## Phase 3: Niri + Noctalia

**Goal:** Replace Hyprland + Waybar + dunst + rofi + hyprlock + hypridle + hyprpaper with niri + noctalia.

### 3.1 — Preparation
- [ ] Create branch: `git checkout -b experiment/niri`
- [ ] Re-read `docs/comparison/niri-and-noctalia.md` and `niri-migration-plan.md`
- [ ] Study vimjoyer's niri wrapper module in detail
- [ ] Study vimjoyer's noctalia config in detail

### 3.2 — Flake Inputs
- [ ] Add `niri-flake` input:
  ```
  niri-flake.url = "github:sodiboo/niri-flake";
  niri-flake.inputs.nixpkgs.follows = "nixpkgs";
  ```
- [ ] Add niri cachix to `nix.settings` (avoids local compilation)
- [ ] `nix flake update`

### 3.3 — Niri System Module
- [ ] Create `modules/features/desktop-niri/default.nix`
  - `programs.niri.enable = true`
  - XDG portals: replace `-hyprland` with `-gnome`
  - PAM: `security.pam.services.swaylock = {}`
  - greetd: change session command to `niri-session`
  - Remove `security.pam.services.hyprlock`
- [ ] In flipper host: disable `desktopHyprland`, enable `desktopNiri`
- [ ] `nixos-rebuild test` (not switch) — activates without becoming boot default
- [ ] Confirm niri session starts and basic keyboard/mouse work

### 3.4 — Niri Program Wrapper
- [ ] Create `modules/programs/niri/default.nix` following vimjoyer's wrapper
  - KDL config generated as a derivation
  - All keybinds (replicate Hyprland binds where possible)
  - Output config (eDP-1, scale, mode)
  - Layout: gaps, focus ring color (Catppuccin Macchiato)
  - `spawn-at-startup` entries
  - Window rules for floating dialogs
  - XWayland via xwayland-satellite

### 3.5 — Replace Waybar Hyprland Modules
- [ ] In waybar wrapper: change `hyprland/workspaces` → `niri/workspaces`
- [ ] In waybar wrapper: change `hyprland/window` → `niri/window`
- [ ] Remove any `hyprctl`-based custom modules

### 3.6 — Noctalia (replaces Waybar + dunst + rofi + lockers)
- [ ] Add noctalia cachix to `nix.settings`
- [ ] Create `modules/programs/noctalia/default.nix` following vimjoyer's config
- [ ] Remove waybar, dunst, rofi wrapper modules from spawn list
- [ ] Configure noctalia: colors (Catppuccin Macchiato), keybinds, plugins
- [ ] Confirm: notifications, launcher, lock screen, idle all work via noctalia

### 3.7 — Cleanup Hyprland
- [ ] Confirm niri + noctalia is stable daily driver (at least one week)
- [ ] Remove `modules/features/desktop-hyprland/default.nix`
- [ ] Remove `modules/programs/hyprpaper`, `hypridle`, `hyprlock`, `rofi`, `dunst` wrappers
- [ ] Remove `hyprland` flake input if no longer needed
- [ ] `git checkout main && git merge experiment/niri`

---

## Phase 4: Graphical Greeter (ReGreet)

**Goal:** Replace plain tuigreet with a styled GTK4 greeter.

- [ ] Research ReGreet config options and theming (GTK CSS)
- [ ] Create branch: `git checkout -b feature/regreet`
- [ ] In `modules/features/desktop-niri/default.nix` (or a new greeter module):
  - `programs.regreet.enable = true`
  - Configure cage as the launch compositor for greetd
  - Apply GTK theme matching Catppuccin Macchiato
  - Set background image
- [ ] `nixos-rebuild test` — confirm greeter appears and login works
- [ ] `nixos-rebuild switch`
- [ ] `git checkout main && git merge feature/regreet`

---

## Ongoing / Deferred

These are not part of the migration sequence but should not be forgotten.

- [ ] **FIDO2 boot unlock** — investigation paused. See `docs/flipper/03-disk-encryption.md` investigation log. Next step: verify libfido2 store path expected by initrd's `libsystemd-shared-259.so`.
- [ ] **Swap encryption** — unencrypted swap is a security gap. Non-trivial to fix (requires hibernation consideration).
- [ ] **hardware.enableRedistributableFirmware = true** — WiFi, BT, audio, NPU firmware on flipper.
- [ ] **Themed greetd session** — tuigreet is plain. Addressed in Phase 4.
- [ ] **YubiKey Bio MPE** — purchase and enroll as primary FIDO2 key. Blocked on FIDO2 boot unlock investigation.
- [ ] **`direnv` + `nix-direnv`** — useful for dev work. Add whenever convenient, independent of migration.
- [ ] **DeepFilterNet noise cancellation** — PipeWire LADSPA plugin. Add post-migration.
- [ ] **`impermanence`** — opt-in persistence on Btrfs. Long-term consideration, requires planning.
- [ ] **Add `major-ant` host** — empty placeholder. Add after dendritic migration (cleaner to onboard a new host into the new structure).
