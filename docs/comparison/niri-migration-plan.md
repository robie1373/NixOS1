# Migration Plan: Dendritic + Wrapper-Modules → Niri + Noctalia

Research date: 2026-03-24. Decisions recorded: 2026-03-24.
Sources: vimjoyer vid79-parts-wrapped, youtube.com/-TRbzkw6Hjs (dendritic), github.com/vimjoyer/nixconf.

---

## Decided Migration Order

```
Phase 0 — Quick wins (immediate, before anything else)
  nh, comma + nix-index-database, wlr-which-key

Phase 1 — Dendritic + wrapper-modules migration
  Convert entire config to vimjoyer's pattern.
  Home-manager retained only for 1Password services.
  ifuse services dropped (insignificant).

Phase 2 — Clean up 1Password / eliminate home-manager
  Understand how to wrap 1Password op/ssh workflow without HM.
  Remove home-manager entirely. HIGH PRIORITY after Phase 1.

Phase 3 — Niri + Noctalia
  Only after dendritic structure is solid.
  Clean architecture makes this straightforward.

Phase 4 — Graphical greeter (ReGreet)
  After niri + noctalia is settled. Isolated change.
```

### Why This Order

The dendritic + wrapper-modules pattern makes each feature a single file, a single derivation, a single place to reason about. That simplicity compounds — every feature added after the migration benefits from it. Adding niri into a clean dendritic structure is straightforward; adding it first and then restructuring means rewriting it.

vimjoyer's config is a proven working reference for the full stack (dendritic + wrapper-modules + niri + noctalia). The intent is to emulate his work, not reinvent it.

### Home-Manager Decision

Home-manager stays alive **only** to protect the 1Password workflow:
- `systemd.user.services.onepassword-gui`
- SSH agent socket + matchBlocks
- `op` CLI integration

Everything else moves to wrapper-modules. The ifuse mount services are insignificant and will be dropped. The ifuse process will be maintained in the documentation to facilitate it's recreation in the new environment.  Eliminating home-manager entirely is a **high priority** once the 1Password wrapper pattern is understood.

---

---

## Q1: How Would the Dendritic Pattern Change My Config?

### What It Is

The dendritic pattern has three rules (from `mightyiam/dendritic`):

1. Each non-entry-point file implements a **single feature**.
2. That file applies the feature **across all configurations it affects** — NixOS + home-manager in the same file.
3. The file lives at a **path that names the feature**.

Auto-discovery via `import-tree` replaces the manual import list in `parts/nixos.nix`. Every `.nix` file under `modules/` is automatically treated as a flake-parts module — no need to register it anywhere.

The other key shift: **`specialArgs` is eliminated**. Because each file is itself a flake-parts module, it already has access to `inputs`, `self`, and `config` natively.

### The vimjoyer Addition: `nix-wrapper-modules`

vimjoyer layers `BirdeeHub/nix-wrapper-modules` on top of the dendritic pattern. Instead of generating config files into `~/.config/`, programs (niri, kitty, fish, etc.) are configured as **Nix derivations** — a configured binary as a package in the Nix store. No home-manager, no dotfiles, no symlinks. This is the "parts-wrapped" part of vid79.

The full vimjoyer stack: **flake-parts + import-tree (dendritic autodiscovery) + wrapper-modules (programs as packages)**.

Wrapper-modules is optional and adventurous. The dendritic import pattern is separable from it.

### Concrete Before/After

**Current `flake.nix`:**
```nix
outputs = inputs @ { flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "aarch64-linux" "x86_64-linux" ];
    imports = [ ./parts/nixos.nix ];
  };
```

**Dendritic `flake.nix`:**
```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  flake-parts.url = "github:hercules-ci/flake-parts";
  import-tree.url = "github:vic/import-tree";
  # ... other inputs ...
};
outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; }
  (inputs.import-tree ./modules);
```

**Current `parts/nixos.nix`** (manual list you maintain):
```nix
{ inputs, ... }:
let mkHost = { system, modules }: inputs.nixpkgs.lib.nixosSystem { ... };
in {
  flake.nixosConfigurations = {
    flipper = mkHost {
      modules = [
        ../modules/system/common.nix
        ../modules/system/audio.nix
        ../modules/system/desktop-hyprland.nix
        # ... you add every new module here manually ...
      ];
    };
  };
}
```

**Dendritic equivalent — `modules/hosts/flipper/default.nix`** (self-contained):
```nix
{ self, inputs, ... }: {
  flake.nixosConfigurations.flipper = inputs.nixpkgs.lib.nixosSystem {
    modules = [ self.nixosModules.flipperConfiguration ];
  };

  flake.nixosModules.flipperConfiguration = { pkgs, ... }: {
    imports = [
      self.nixosModules.common
      self.nixosModules.audio
      self.nixosModules.desktopHyprland
    ];
    networking.hostName = "flipper";
    system.stateVersion = "24.05";
  };
}
```

**Current `modules/system/audio.nix`** (system-only; home config is in a separate file):
```nix
{ lib, config, pkgs, ... }: {
  options.mySystem.audio.enable = lib.mkEnableOption "PipeWire audio";
  config = lib.mkIf config.mySystem.audio.enable {
    services.pipewire.enable = true;
    # ...
  };
}
```

**Dendritic `modules/audio.nix`** (system AND home in one file, registered as a flake-parts module):
```nix
{ self, ... }: {
  flake.nixosModules.audio = { pkgs, lib, ... }: {
    services.pipewire.enable = true;
    services.pipewire.alsa.enable = true;
    services.pipewire.pulse.enable = true;
    hardware.pulseaudio.enable = false;
  };
}
```

### File Change Summary

| Current | Dendritic equivalent |
|---|---|
| `flake.nix` | Rewritten to use `import-tree` |
| `parts/nixos.nix` | **Deleted** — replaced by per-host files under `modules/hosts/` |
| `modules/system/*.nix` | Restructured into `modules/features/*.nix`, each a flake-parts module |
| `modules/home/*.nix` | Merged into same feature files (or kept separate, auto-discovered) |
| `hosts/flipper/configuration.nix` | Becomes `modules/hosts/flipper/default.nix` |

### What You Gain / Lose

**Gains:**
- Add a file, it's automatically included — no manual import list
- Each feature is self-contained (NixOS + home-manager together)
- `specialArgs` eliminated
- Easy to copy a single feature to a new host

**Costs:**
- This is a significant structural rewrite — not incremental
- The `mkEnableOption` pattern can still exist, but the purpose shifts slightly
- `wrapper-modules` is an additional learning curve (optional)

**Recommendation:** This is a worthwhile long-term direction for Dry Dock, especially as more hosts are added. Do **not** attempt it concurrently with the niri experiment — do them in separate sessions.

---

## Q2: Cleanest + Safest Way to Try Niri + Noctalia

### Is a Git Branch Necessary for Safety?

**NixOS generations are a reliable rollback mechanism** for compositor-level changes. `sudo nixos-rollback` or selecting the previous generation at boot restores the entire system. You don't need a branch purely for safety.

That said, **a git branch is still recommended** — not for rollback, but because:
- You get a clean diff of everything that changed
- Your `main` branch stays clean
- You can iterate without polluting commit history
- If you decide not to proceed, it's trivially discardable

### Recommended Approach: Parallel Feature Module

Niri and Hyprland can coexist. `programs.niri.enable` and `programs.hyprland.enable` can both be true simultaneously. greetd is the switchboard.

**Step by step:**

1. **Create a branch:** `git checkout -b experiment/niri`

2. **Add niri input to `flake.nix`:**
   ```nix
   niri-flake.url = "github:sodiboo/niri-flake";
   niri-flake.inputs.nixpkgs.follows = "nixpkgs";
   ```
   (noctalia-shell is in nixpkgs-unstable, no extra input needed)

3. **Create `modules/system/desktop-niri.nix`** with its own `mkEnableOption`. Do not touch the Hyprland module.

4. **In `hosts/flipper/configuration.nix`**, flip the flag:
   ```nix
   mySystem.desktopHyprland.enable = false;
   mySystem.desktopNiri.enable      = true;
   ```

5. **`nixos-rebuild test` first** (not `switch`) — this activates without making it the boot default. If it breaks, reboot → Hyprland returns automatically.

6. Once satisfied: `nixos-rebuild switch`.

### Known Gotchas

- **greetd session:** niri uses `niri-session` (not bare `niri`) so environment variables get exported to systemd + D-Bus.
- **XDG portals:** Replace `xdg-desktop-portal-hyprland` with `xdg-desktop-portal-gnome` (or `-gtk`). Screencasting uses gnome portal.
- **PAM rules:** `security.pam.services.hyprlock` is Hyprland-specific; niri with swaylock needs `security.pam.services.swaylock = {}`.
- **Noctalia:** Newer project; may have rough edges. Can be added after niri is stable.
- **wrapper-modules for niri:** This is vimjoyer's approach. Optional. Start with `programs.niri.enable = true` + plain KDL config. Explore wrapper-modules separately.

---

## Q3: Features from vimjoyer's Config Worth Having

### `wlr-which-key` — Visual Keybinding Cheatsheet ⭐
A popup keybinding menu (triggered by `Mod+?` or `Mod+d`). Shows a visual overlay of available chords — bluetooth, wifi, apps, audio mixer, etc. Much nicer than memorizing binds. Works with both Hyprland and niri. Available in nixpkgs as `wlr-which-key`.

### `nh` — Better Rebuild UX ⭐
`nh os switch` wraps `nixos-rebuild` with prettier output, diffs between generations, and cleaner status display. The `rebuild`/`build`/`ntest` aliases stay useful; `nh` adds visual clarity to what's actually changing. In nixpkgs.

### `comma` + `nix-index-database` ⭐
The `,` command: run any binary from nixpkgs without installing it. `, ffmpeg ...` just works. Uses a pre-built index (no local `nix-index` scan required). Pairs with `nix-index` for `command-not-found` integration. Immediate quality-of-life improvement.

### `direnv` + `nix-direnv`
Auto-activates dev shells when you `cd` into a project with a `flake.nix` or `.envrc`. Essential for any development work. Available in nixpkgs with a home-manager module.

### DeepFilterNet Noise Cancellation
AI microphone noise cancellation as a PipeWire LADSPA plugin. Works in software, no hardware required. Useful for calls on a laptop. Creates a virtual "clean mic" sink. Config is in vimjoyer's `modules/nixos/features/pipewire.nix`.

### `swappy` — Screenshot Annotation
Wayland screenshot annotation tool. Capture a region → paste into swappy → draw/annotate → copy/save. Pairs with your existing screenshot setup.

### `impermanence` — Opt-in Persistence (Advanced)
Root filesystem is wiped on every boot. Only explicitly declared paths are persisted. Forces you to be explicit about what state matters; makes the system truly reproducible. Requires Btrfs subvolumes (flipper already has disko). Medium-term consideration — not something to do soon.

### Centralized Theme as `self.theme`
vimjoyer defines his color palette once in `modules/theme.nix` and exports it as `self.theme` (with `#`) and `self.themeNoHash` (without). Every wrapped program reads from this. Your Catppuccin is already consistent via packages, but this pattern makes a theme change a one-file edit. Relevant when/if dendritic migration happens.

---

## Q4: When to Replace tuigreet with a Graphical Greeter?

### What vimjoyer Uses

Notably: **nothing**. The public nixconf repo has no greeter configuration at all. No greetd, no tuigreet, no regreet, no SDDM. He either uses autologin or handles it outside the repo.

### Options

| Greeter | Notes |
|---|---|
| **ReGreet** (`programs.regreet.enable`) | GTK4, clean, runs under cage or sway. Most commonly recommended for greetd setups. NixOS has first-class support. |
| **greetd + gtkgreet** | Older GTK3 option, less maintained. |
| **SDDM** | KDE display manager, heavier, Wayland-compatible. You had this previously with KDE. |
| **niri-greet pattern** | niri → regreet → niri (a niri bootstrap session launches regreet). More complex. |

### When to Do It

**After niri is stable and settled.** Rationale:

- tuigreet is session-agnostic — adding niri as a session is just adding the session entry, not changing the greeter itself.
- A graphical greeter is another potential failure point. During a compositor migration, minimize moving parts.
- Once niri + noctalia is your daily driver, swapping the greeter is a clean isolated step: `programs.regreet.enable = true`, configure cage, update greetd default_session. It touches nothing in the compositor config.

**Recommended order:**
1. Get niri working
2. Get noctalia working
3. Then swap tuigreet → ReGreet as a standalone change

---

## Q5: When to Swap foot for kitty?

### Current State

- **flipper** (physical host, real GPU): **already uses kitty** ✓
- **nixos1** (aarch64 QEMU VM): **uses foot** — intentional, correct

### Why foot Stays on VMs

kitty requires real OpenGL. QEMU's virtual GPU does not provide it. This is documented in CLAUDE.md. foot is CPU-rendered and works everywhere.

### The Answer

For flipper: **already done**.

For nixos1: **foot stays, permanently**, unless the VM gets GPU passthrough or VirtIO-GPU-GL enabled. This is not a migration step — it's the correct permanent end state.

vimjoyer uses kitty throughout because he has only physical machines in his config.

---

## Recommended Migration Order

See the **Decided Migration Order** section at the top of this document — that reflects actual decisions made 2026-03-24.

---

## Sources
- [vimjoyer vid79-parts-wrapped](https://www.vimjoyer.com/vid79-parts-wrapped)
- [vimjoyer/nixconf GitHub](https://github.com/vimjoyer/nixconf)
- [The dendritic pattern — NixOS Discourse](https://discourse.nixos.org/t/the-dendritic-pattern/61271)
- [mightyiam/dendritic](https://github.com/mightyiam/dendritic)
- [BirdeeHub/nix-wrapper-modules](https://birdeehub.github.io/nix-wrapper-modules/md/intro.html)
- [sodiboo/niri-flake](https://github.com/sodiboo/niri-flake)
- [rharish101/ReGreet](https://github.com/rharish101/ReGreet)
