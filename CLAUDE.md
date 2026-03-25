# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: "Dry Dock"

Robie's NixOS fleet configuration. Goals: DRY, modular, flexible. Uses flake-parts to organize a multi-host NixOS + Home Manager setup.

**Assume planning mode always — do not make changes unless explicitly asked.**

**Always use current NixOS option syntax.** Never use deprecated aliases — use the renamed form even if the alias still works. When in doubt, check nixpkgs source or search.nixos.org. Config longevity is a priority.

## Model use — subagent delegation

This session runs on Sonnet (supervisor). Discrete mechanical subtasks should be delegated to Haiku subagents via the Agent tool to preserve Sonnet context and cost.

**Good Haiku candidates in this project:**

- Searching nixpkgs/NixOS option documentation for correct current syntax (e.g. "what is the current non-deprecated option for X?")
- Reading multiple files to summarise current state — e.g. scanning all `modules/home/*.nix` to list which `myHome` options exist, or reading `parts/nixos.nix` to list all host module imports
- Checking `docs/` files for relevant existing documentation before planning new work
- Summarising BEARING.md pending tasks or extracting specific notes
- Writing or updating docs files in `docs/` once the content is decided
- Grepping for option names, attribute paths, or patterns across the repo (e.g. finding all places a deprecated alias is used)
- Diffing or comparing two config files to report differences
- Drafting routine BEARING.md updates (moving completed items, writing outcome notes)

**Keep on Sonnet:**

- Any Nix reasoning that crosses module boundaries — e.g. working out why a home-manager activation error occurs, or how `useGlobalPkgs` interacts with `allowUnfreePredicate`
- Architecture decisions: adding a host, restructuring `parts/nixos.nix`, deciding module namespace layout
- Debugging build failures — attribute errors, infinite recursion, type mismatches
- Anything touching LUKS/TPM2/FIDO2, disko, or hardware-specific config where a wrong change bricks the machine
- Security-relevant changes (polkit rules, SSH config, 1Password integration)
- Planning new features: reading, reasoning about options, writing the plan in docs/ before implementing

**Invocation example:**

```python
Agent(prompt="Read modules/home/ and list every myHome option defined", model="haiku")
```

---

## Git practices

Commit frequently. Small, atomic commits are strongly preferred — any time a logical unit of work is complete (a module option is added, a script is fixed, a build is verified), commit it without waiting to be asked.

**Commit messages:** Write them. Robie's own messages are intentionally minimal — yours should be detailed: what changed, why it changed, and any context that will matter in six months. Use imperative mood ("Add bearing-activity timer", "Fix SSH_AUTH_SOCK in briefing service"). Do not use "I", "Claude", or "we" — these are Robie's commits documenting his work. You are the instrument; the work is his.

**Commit transparently:** Make commits as part of normal work. Mention what you committed in passing ("committed the timer fix") but don't make a production of it. Never ask permission for routine commits.

**Pushing:** Never push to origin without being asked. After a productive session with several commits, offer once: "Want me to push this to origin?" — don't repeat it if he declines.

---

## Key Commands

All run from `~/nixos-config/` on the target host:

```bash
# Apply config (shell alias)
rebuild        # → sudo nixos-rebuild switch --flake .#<hostname>

# Build without activating (check for errors)
build          # → nixos-rebuild build --flake .#<hostname>

# Test without making it the boot default
ntest          # → sudo nixos-rebuild test --flake .#<hostname>

# Update all flake inputs
nix flake update

# Rollback if something breaks
sudo nixos-rollback
git checkout flake.lock   # revert lock file
```

## Architecture

### Flake Structure

`flake.nix` is minimal — just inputs and a `flake-parts.lib.mkFlake` call that imports `parts/nixos.nix`.

`parts/nixos.nix` is where all hosts are defined via a `mkHost` helper:
```nix
mkHost = { system, modules }: inputs.nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs; };
  inherit system modules;
};
```

Each host in `flake.nixosConfigurations` lists its system modules and inline home-manager config (with per-user home module imports).

### Module Pattern

All feature modules use `mkEnableOption` + `mkIf`. Two namespaces:

- `mySystem.<featureName>.enable` — system modules (`modules/system/`)
- `myHome.<featureName>.enable` — home modules (`modules/home/`)

```nix
# system module example
options.mySystem.audio.enable = lib.mkEnableOption "PipeWire audio";
config = lib.mkIf config.mySystem.audio.enable { ... };

# home module example
options.myHome.mpv.enable = lib.mkEnableOption "mpv video player";
config = lib.mkIf config.myHome.mpv.enable { ... };
```

Hosts enable system features in `hosts/<name>/configuration.nix`:
```nix
mySystem.audio.enable           = true;
mySystem.desktopHyprland.enable = true;
```

Home features are enabled in `hosts/<name>/home.nix`:
```nix
myHome.mpv.enable    = true;
myHome.yazi.enable   = true;
```

System modules are listed in `parts/nixos.nix`, **not** in `configuration.nix`.

### Split: System vs Home

- `modules/system/` — NixOS system config (services, hardware, polkit, fonts)
- `modules/home/` — Home Manager config (dotfiles, user programs, shell)

Both halves must be listed separately in `parts/nixos.nix` — the system modules in the top-level `modules` list, the home modules inside the inline `home-manager.users.robie.imports` list.

### Home Manager Setup

- `useGlobalPkgs = true` and `useUserPackages = true` — pkgs comes from system nixpkgs
- `backupFileExtension = "backup"` — prevents activation failure when files exist (e.g. GTK files written by KDE)
- `allowUnfreePredicate` belongs in `modules/system/common.nix`, not in home modules (dead with useGlobalPkgs)
- Each host has its own `hosts/<name>/home.nix` containing only `home.stateVersion`

### Active Hosts

| Host | Arch | Notes |
|------|------|-------|
| flipper | x86_64 | Main laptop, disko disk encryption, FIDO2/TPM2 unlock |
| nixos1 | aarch64 | QEMU VM |

### Inputs

- `nixpkgs`: unstable branch
- `home-manager`: follows nixpkgs
- `flake-parts`: nixpkgs-lib follows nixpkgs
- `hyprland`: direct upstream (not from nixpkgs)
- `disko`: disk partitioning (used on flipper)

## Adding a New Host

1. Run `nixos-generate-config` on target → get `hardware-configuration.nix` + `stateVersion`
2. Copy `hardware-configuration.nix` to `hosts/<name>/`
3. Create `hosts/<name>/configuration.nix` (based on an existing host, set correct `stateVersion`, hostname, feature flags)
4. Create `hosts/<name>/home.nix` with correct `home.stateVersion`
5. Add `mkHost` block to `parts/nixos.nix` with appropriate system and home module lists

## The Bearing

This project coordinates with The Bearing — Robie's life and project tracker (`~/work/`).

**"Read the bearing"** — when asked, check `BEARING.md` in the root of this repo:
- Review **Pending** tasks delegated from The Bearing
- Check **Notes to The Bearing** from previous sessions
- Report what's there, then ask if you should start on anything

**After completing delegated work:** Update `BEARING.md` — move items to Completed with a brief outcome, add findings to Notes to The Bearing. The Bearing monitors `~/work/DELEGATIONS.md` for status updates.

---

## docs/ Directory

The `docs/` directory is Robie's notebook and textbook for understanding the system. Treat it as a first-class deliverable alongside the code.

**Keep guides up to date when making changes.** If a config change affects something documented in docs/ (hardware behavior, a module's rationale, a workflow), update the relevant guide in the same session.

**Record planning in docs/ before new work.** When planning a new feature or investigating a problem, write up the plan, options considered, and reasoning in a new or existing guide file before implementing. This is the record of *why* decisions were made.

The `docs/` directory contains detailed reference docs — consult these before making hardware or desktop config changes:

- `docs/flipper/README.md` — hardware compatibility table for the ASUS Vivobook 14 Flip (flipper). Documents what works, what's broken, and why (speakers firmware, ISH accelerometer, media keys, NPU, etc.)
- `docs/flipper/03-disk-encryption.md` — LUKS + TPM2 + FIDO2/YubiKey setup
- `docs/hyprland/` — rationale for tool choices (greetd vs SDDM, foot vs kitty, Catppuccin) and troubleshooting
- `docs/apps/README.md` — app stack overview (mpv, zathura, imv, MPD/ncmpcpp, yazi, NAS mount)

**foot vs kitty:** VMs use `foot` (CPU-rendered, works everywhere). Physical hosts use `kitty` (GPU-accelerated, requires real OpenGL — fails on QEMU/KVM virtual GPUs).

## Adding a New Feature Module

1. Create `modules/system/<name>.nix` and/or `modules/home/<name>.nix`
2. Define `options.mySystem.<name>.enable = lib.mkEnableOption "..."` in the system module
3. Add the module file to the relevant host's module list in `parts/nixos.nix`
4. Enable it in `hosts/<hostname>/configuration.nix`
