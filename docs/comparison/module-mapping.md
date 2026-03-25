# Module Mapping: Current → Dendritic

Migration reference for Phase 1. Maps every current module to its destination in the
dendritic structure. Decisions from the 2026-03-25 planning discussion are recorded here.

Reference: `docs/migration-checklist.md` for sequenced steps.
Reference: `github.com/vimjoyer/nixconf` for structural patterns.

---

## Decisions Made (2026-03-25)

### 1. Drop `mySystem.*` / `myHome.*` enable flags

The `mkEnableOption` + `mkIf` pattern is dropped in the migrated config. Feature
presence is controlled by selective imports in the host file — you either import a
module or you don't. This removes boilerplate from every module and makes the host
file the single honest record of what that host does.

Modules that currently have no option (common.nix, 1password.nix) already follow
this pattern and need no change in approach.

### 2. Home-manager stays through Phase 1

HM is retained for all home config through the Phase 1 migration. It is eliminated
in Phase 2 alongside the 1Password work. `hjem` is not on the roadmap but is kept
in mind as a fallback if problems arise that it solves cleanly.

### 3. Theme as a first-class flake output

Catppuccin Macchiato palette is extracted to `modules/theme.nix` before any programs
are wrapped. Every wrapper imports `self.theme` for colors rather than hardcoding
hex values. This is done as the first step of Phase 1 before touching any modules.

### 4. 1Password in Phase 2

1Password stays in HM through Phase 1. Phase 2 moves all three pieces (SSH agent
socket, SSH matchBlocks, GUI daemon service) to system-level NixOS config. The work
is mechanical — the hard part (understanding what 1Password requires) is already done.
A dedicated planning doc is written before any Phase 2 implementation.

---

## System Modules

| Current file | Current option | New location | Notes |
|---|---|---|---|
| `modules/system/common.nix` | *(unconditional)* | `modules/nixos/common/default.nix` | Boot, networking, locale, users, fish, git, neovim, tailscale, nh, disko |
| `modules/system/audio.nix` | `mySystem.audio.enable` | `modules/nixos/audio/default.nix` | Drop mkEnableOption; import-based toggle |
| `modules/system/desktop-hyprland.nix` | `mySystem.desktopHyprland.enable` | `modules/nixos/desktop-hyprland/default.nix` | System side only — portals, greetd, fonts, Bluetooth, env vars |
| `modules/system/desktop-kde.nix` | `mySystem.desktopKde.enable` | `modules/nixos/desktop-kde/default.nix` | Low priority; not used on flipper |
| `modules/system/vm-guest.nix` | `mySystem.vmGuest.enable` | `modules/nixos/vm-guest/default.nix` | QEMU guest + SPICE |
| `modules/system/1password.nix` | *(unconditional)* | `modules/nixos/1password/default.nix` | System packages + polkit only; home side stays in HM through Phase 1 |
| `modules/system/speaker-fix.nix` | `mySystem.speakerFix.enable` | `modules/nixos/speaker-fix/default.nix` | flipper-specific; TAS2781 i2c register fix |

---

## Home Modules (HM — retained through Phase 1)

These stay as home-manager modules. They move to `modules/home/` in the new structure
(same location, just under the new directory tree). Program configs that can be wrapped
move to `modules/wrappedPrograms/` in Phase 1.7.

| Current file | Current option | Phase 1 disposition | Notes |
|---|---|---|---|
| `modules/home/common.nix` | *(unconditional)* | Keep as HM module | Shell aliases, git config, nix-index/comma, home packages |
| `modules/home/1password.nix` | *(unconditional)* | Keep as HM module — Phase 2 target | SSH agent socket, matchBlocks, GUI daemon service |
| `modules/home/bearing.nix` | `myHome.bearing.enable` | Keep as HM module | Scripts + timers; no wrapping candidate |
| `modules/home/claude.nix` | *(unconditional)* | Keep or fold into common | `programs.claude-code.enable` — trivial |
| `modules/home/gemini-cli.nix` | *(unconditional)* | Keep or fold into common | `programs.gemini-cli.enable` — trivial |
| `modules/home/obsidian.nix` | *(unconditional)* | Keep or fold into common | Single package |
| `modules/home/desktop-hyprland.nix` | `myHome.desktopHyprland.enable` | Split: wrapped programs extract out; remainder stays HM | See wrappedPrograms table below |

---

## Programs → Wrapper-Modules

These are extracted from `modules/home/desktop-hyprland.nix` and become wrapped
derivations in `modules/wrappedPrograms/`. Each gets `self.theme` injected for
Catppuccin Macchiato colors.

| Program | Current location | New location | Notes |
|---|---|---|---|
| `kitty` | `desktop-hyprland.nix` | `modules/wrappedPrograms/kitty.nix` | Font, theme, keybinds |
| `fish` | `desktop-hyprland.nix` | `modules/wrappedPrograms/fish.nix` | Functions, prompt — or keep in HM `programs.fish` |
| `waybar` | `desktop-hyprland.nix` | `modules/wrappedPrograms/waybar.nix` | Full config + CSS; iphone module stays |
| `rofi` | `desktop-hyprland.nix` | `modules/wrappedPrograms/rofi.nix` | Catppuccin theme |
| `dunst` | `desktop-hyprland.nix` | `modules/wrappedPrograms/dunst.nix` | Bearing dunst rule must carry over |
| `hyprpaper` | `desktop-hyprland.nix` | `modules/wrappedPrograms/hyprpaper.nix` | Wallpaper path |
| `hypridle` | `desktop-hyprland.nix` | `modules/wrappedPrograms/hypridle.nix` | Timeouts |
| `hyprlock` | `desktop-hyprland.nix` | `modules/wrappedPrograms/hyprlock.nix` | Lock screen config |
| `wlr-which-key` | `desktop-hyprland.nix` | `modules/wrappedPrograms/wlr-which-key.nix` | YAML config with Catppuccin |
| `foot` | `desktop-hyprland.nix` | Keep in HM or wrap | VM terminal; foot stays on nixos1 |
| GTK/Qt theme | `desktop-hyprland.nix` | Keep in HM (`gtk.*`, `qt.*`) | No wrapper-modules equivalent; HM handles this cleanly |
| ifuse/iPhone | `desktop-hyprland.nix` | Keep in HM or system module | Low priority; checklist item 1.10 to drop the service |

---

## Host Files

| Current | New | Notes |
|---|---|---|
| `parts/nixos.nix` | Replaced by `import-tree` + `modules/flake-parts.nix` | Host list still explicit; import-tree handles module discovery |
| `hosts/flipper/configuration.nix` | `modules/nixos/hosts/flipper/default.nix` | Import list replaces mySystem.*.enable flags |
| `hosts/flipper/home.nix` | `modules/nixos/hosts/flipper/default.nix` (inline) or separate | home.stateVersion + myHome.*.enable equivalents |
| `hosts/nixos1/configuration.nix` | `modules/nixos/hosts/nixos1/default.nix` | Same pattern |
| `hosts/nixos1/home.nix` | Same as above | |
| `hosts/*/hardware-configuration.nix` | `modules/nixos/hosts/*/hardware-configuration.nix` | Copy, never edit |

---

## Gaps (no vimjoyer equivalent)

These have no reference implementation in vimjoyer/nixconf. Original work required.

| Feature | Current location | Plan |
|---|---|---|
| 1Password SSH agent + GUI daemon | `modules/home/1password.nix` | Phase 2: system-level NixOS config; planning doc before implementation |
| NAS SMB mount | flipper-specific | Keep as system or home module; no wrapping candidate |
| The Bearing | `modules/home/bearing.nix` | Keep as HM module; it's scripts + timers, wrapping adds nothing |
| Speaker fix | `modules/system/speaker-fix.nix` | Keep as system module; hardware-specific |
| FIDO2/LUKS config | `hosts/flipper/configuration.nix` | Keep in host config; hardware-specific, never generalise |
| Hyprshot | home module | Keep as HM module |
| Anki | home module | Keep as HM module |

---

## New Files (no current equivalent)

| File | Purpose |
|---|---|
| `modules/theme.nix` | Catppuccin Macchiato palette as `self.theme`; injected into all wrappers |
| `modules/flake-parts.nix` | Host list + flake output schema (replaces `parts/nixos.nix`) |
