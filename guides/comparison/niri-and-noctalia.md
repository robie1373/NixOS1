# Niri and Noctalia: Exploration Notes

Research date: 2026-03-23. Written from the perspective of a daily Hyprland + fish shell user on NixOS (flipper).

---

## Part 1: Niri — Scrollable-Tiling Wayland Compositor

### What is niri?

Niri is a Wayland compositor written in Rust. Its defining characteristic is **scrollable tiling**: windows are arranged in columns on an infinite horizontal strip, and you scroll left/right to reach them. This is inspired by PaperWM (a GNOME Shell extension) and Karousel (KDE).

The project is maintained by YaLTeR (Ivan). It reached stability for daily use and is actively developed. As of early 2026, it uses calendar versioning (25.01, 25.05, 25.08, etc.) and has a responsive Matrix community.

**Repo:** https://github.com/niri-wm/niri

---

### Window Management Model: Scrollable Tiling vs Dynamic Tiling

This is the most fundamental difference from Hyprland.

**Hyprland (dynamic tiling):**
- Every monitor has numbered workspaces.
- When you open a window on a workspace, Hyprland tiles it alongside existing windows, splitting and shrinking them.
- You switch between workspaces with `Super+1`, `Super+2`, etc.
- You mentally bucket apps into discrete workspaces.
- Moving windows between workspaces is constant workflow overhead.

**Niri (scrollable tiling):**
- Each monitor has its own **infinite horizontal strip** of columns.
- Opening a new window adds a column to the right. **Existing windows never resize.**
- You scroll left/right through your open windows with `Mod+Left/Right` or `Mod+H/L`.
- Workspaces exist but are **vertical**, stacked per monitor, and are dynamic (one always-empty workspace at the bottom). Each monitor has its own independent workspace set.
- The mental model: instead of "which workspace is this on?", you just scroll to find it.

In the words of one user: "If you want everything to tile by default and your desktop shrinks for each app you have open then maybe Hyprland is what you want. If you want a huge scrolling desktop where you get to control when windows is tiled then niri is a great fit."

**Floating windows** are supported since niri 25.01. They live in a separate layer above tiled windows and don't participate in scrolling. You can toggle between floating and tiling per-window. Dialogs and fixed-size windows auto-float.

**Column layout:** Windows can be grouped into columns (side-by-side), giving you a 2D arrangement: columns scroll horizontally, and within a column, windows are stacked vertically. This is more expressive than Hyprland's dwindle/master for certain workflows.

**Window tabs:** Since 25.05 or so, niri gained support for grouping windows into tabs within a column — multiple windows in the same space, switchable by tab.

---

### IPC and Scripting

Niri has a robust `niri msg` CLI for IPC. Examples:

```sh
# Focus management
niri msg action focus-window-left
niri msg action focus-window-right

# Move windows
niri msg action move-window-left
niri msg action move-window-right

# Close a window
niri msg action close-window

# List all windows (with IDs, app-ids, titles)
niri msg windows

# List workspaces
niri msg workspaces

# List layer-shell surfaces (useful for debugging bars)
niri msg layers

# Reload config
niri msg action reload-config

# Load a specific config file at runtime (since 25.11)
niri msg action load-config-file --path /path/to/config.kdl

# Power management
niri msg action power-off-monitors
niri msg action power-on-monitors

# Pick a window interactively (useful for scripts)
niri msg pick-window

# Pick a pixel color
niri msg pick-color
```

The IPC also exposes an **event stream** that emits compositor events (workspace changes, window focus changes, etc.) in a format suitable for status bar widgets. Waybar's niri modules use this directly.

Window and workspace objects have stable unique IDs across the session, so you can write scripts that address specific windows reliably.

---

### Configuration Format

Niri uses **KDL** (KDL Document Language), not Nix and not TOML/YAML. Config lives at `~/.config/niri/config.kdl`.

Key features of the config:
- **Live reload**: Save the file and changes apply immediately. An invalid config does not crash niri — it shows an error and preserves the last working state.
- `niri validate` checks the config without a running session.
- **No defaults loaded**: Unlike Hyprland which ships with some defaults, niri loads *nothing* unless you configure it. If you don't define a keybind for opening a terminal, there is none. This is a clean-slate philosophy.

Config structure:

```kdl
input {
  keyboard { xkb { layout "us"; } }
  touchpad { natural-scroll; }
}

output "eDP-1" {
  mode "2560x1600@60.003"
  scale 2.0
}

layout {
  gaps 8
  focus-ring { width 2; active-color "#c6a0f6"; }
  border { width 2; active-color "#8aadf4"; }
  shadow { on; }
}

spawn-at-startup "waybar"
spawn-at-startup "swayidle" "-w" "timeout" "300" "swaylock -f" "timeout" "600" "niri msg action power-off-monitors"
spawn-at-startup "mako"
spawn-at-startup "swaybg" "-i" "/path/to/wallpaper.png" "-m" "fill"

binds {
  Mod+Return { spawn "kitty"; }
  Mod+D { spawn "fuzzel"; }
  Mod+U { close-window; }

  Mod+Left  { focus-column-left; }
  Mod+Right { focus-column-right; }
  Mod+H     { focus-column-left; }
  Mod+L     { focus-column-right; }
  Mod+K     { focus-window-or-workspace-up; }
  Mod+J     { focus-window-or-workspace-down; }

  Mod+Shift+Left  { move-column-left; }
  Mod+Shift+Right { move-column-right; }

  Mod+1 { focus-workspace 1; }
  Mod+2 { focus-workspace 2; }
  Mod+3 { focus-workspace 3; }

  Mod+Shift+1 { move-window-to-workspace 1; }
  Mod+Shift+2 { move-window-to-workspace 2; }

  Mod+F { maximize-column; }
  Mod+Shift+F { fullscreen-window; }
  Mod+V { toggle-window-floating; }

  XF86AudioRaiseVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
  XF86AudioLowerVolume  allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
  XF86AudioMute         allow-when-locked=true { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
  XF86MonBrightnessUp   allow-when-locked=true { spawn "brightnessctl" "set" "10%+"; }
  XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "set" "10%-"; }

  Super+Alt+L { spawn "swaylock" "-f"; }
  Print { screenshot; }
}

window-rule {
  match app-id=r#"pavucontrol"#
  open-floating true
}
```

Note: `Mod` means Super when running on a TTY, Alt when running nested (useful for testing in a window).

---

### Wayland Protocol Support

Niri implements all the important protocols:

| Protocol | Status |
|---|---|
| xdg-shell | Yes |
| layer-shell (wlr-layer-shell) | Yes |
| wlr-screencopy | Yes |
| ext-idle-notify | Yes |
| ext-session-lock | Yes |
| idle-inhibit | Yes |
| gamma-control | Yes |
| xdg-activation | Yes |
| pointer-gestures | Yes |
| tablet protocol | Partial (no touchscreen gestures as of 2026) |

Screencasting uses xdg-desktop-portal-gnome. This is the same portal used by many apps (OBS, browser screen sharing, Discord). It requires gnome-keyring or equivalent.

**XWayland:** Niri does not implement XWayland internally (it lacks a global coordinate system that X11 requires). Instead, since niri 25.08, it integrates **xwayland-satellite** (`xwayland-satellite >= 0.7`) as a separate rootless XWayland bridge. This is configured via a `xwayland` block in the config. In practice, xwayland-satellite handles Steam, Discord, Wine apps, and other X11 software transparently. See the niri wiki's Xwayland page for details.

---

### Status Bar: Waybar

Waybar supports niri natively since Waybar 0.11.0 (included in nixpkgs unstable). The niri-specific modules are:

- `niri/workspaces` — workspace buttons (replaces `hyprland/workspaces`)
- `niri/window` — focused window title
- `niri/language` — current keyboard layout

Everything else in your existing Waybar config (battery, backlight, cpu, memory, network, pulseaudio, bluetooth, tray, custom modules) carries over unchanged. The only thing to update is replacing `hyprland/workspaces` with `niri/workspaces`.

Waybar uses niri's IPC event stream for its niri modules, so it stays in sync efficiently without polling.

---

### Idle Management and Screen Locking

Niri works with standard Wayland idle/lock tools via the protocols it implements:

**Idle detection:** `swayidle` (uses `ext-idle-notify`) works directly. Example:

```sh
swayidle -w \
  timeout 300 'swaylock -f' \
  timeout 600 'niri msg action power-off-monitors' \
  resume 'niri msg action power-on-monitors' \
  before-sleep 'swaylock -f'
```

`hypridle` also works with niri (it uses the same `ext-idle-notify` protocol). You'd configure it the same way you would for Hyprland, but replace any `hyprctl` calls with `niri msg` calls.

**Screen locking:**
- `swaylock` — standard, works out of the box. Requires `security.pam.services.swaylock = {}` on NixOS.
- `hyprlock` — also works with niri (it implements ext-session-lock, which niri supports). Some users prefer hyprlock's appearance.

**Idle inhibit:** niri implements the idle-inhibit protocol, so mpv and other media apps that inhibit idle work correctly. There is a known edge case where fullscreen idle inhibition may not work in all browsers outside of Firefox (GitHub issue #2114 was open as of early 2026).

---

### Hotkey Daemon

Niri does not use a separate hotkey daemon. All keybinds are defined in `config.kdl` in the `binds { }` block. This is conceptually identical to Hyprland's `bind =` lines.

Notable features:
- `allow-when-locked=true` on a bind makes it active even when the session is locked (equivalent to Hyprland's `bindl`).
- `repeat=false` disables key repeat for a bind.
- `cooldown-ms=150` sets a minimum time between activations.
- `allow-inhibiting=false` makes niri always process the bind even if an inhibitor is active.

There is no `bindel` equivalent per se — repeating locked binds are done by combining `allow-when-locked=true` with the default repeat behavior.

---

### Display Manager / Session Start

The Hyprland setup uses `greetd` + `tuigreet` launching `start-hyprland`. Niri integrates similarly.

For NixOS, `programs.niri.enable = true` installs a niri session that greetd (or any display manager) can pick up. To start with tuigreet:

```nix
services.greetd.settings.default_session.command =
  "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
```

`niri-session` (vs just `niri`) imports environment variables into systemd and D-Bus so that systemd user services (like dunst, hypridle) can find them. This is the recommended way to start niri.

---

### NixOS Configuration

**Option 1: nixpkgs (simplest)**

```nix
# In configuration.nix
programs.niri.enable = true;
```

This installs niri and registers the session. Config is written manually to `~/.config/niri/config.kdl` (or managed via `xdg.configFile` in Home Manager).

**Option 2: sodiboo/niri-flake (more powerful)**

The niri-flake provides:
- Declarative Nix config via `programs.niri.settings` (generates KDL at build time)
- Build-time schema validation — config is always in sync with the installed niri version
- Choice between `niri-stable` and `niri-unstable` packages
- Home Manager module (`homeModules.niri` and `homeModules.config`)
- Stylix integration for automatic theming
- Pre-built binaries via Cachix (`niri.cachix.org`) — avoids local compilation

Add to flake inputs:
```nix
niri.url = "github:sodiboo/niri-flake";
```

Then in NixOS config:
```nix
# system module
programs.niri.enable = true;
# (niri-flake's nixosModule sets up polkit, portals, keyring automatically)
```

Home Manager config with declarative settings:
```nix
programs.niri.settings = {
  input.keyboard.xkb.layout = "us";
  layout.gaps = 8;
  binds = { "Mod+Return".action.spawn = ["kitty"]; };
};
```

**Important gotchas on NixOS:**
- With no config file at all, niri starts but you cannot launch anything (no keybinds, no terminal). Always seed a config.
- The NixOS wiki warns: "Without Configuration or Additional Setup, you may be unable to launch apps."
- If using `programs.waybar.enable` via Home Manager AND `spawn-at-startup "waybar"` in the niri config, Waybar launches twice. Remove the spawn line or don't use HM's waybar service.
- For X11 Electron/Chromium apps: set `NIXOS_OZONE_WL=1` in `environment.sessionVariables`.
- `security.pam.services.swaylock = {}` is needed if using swaylock.
- Portal for file pickers: `xdg-desktop-portal-gtk` alongside `xdg-desktop-portal-gnome`.

---

### What Changes Coming From Hyprland

Here is a practical mapping for this specific setup:

| Hyprland component | Niri equivalent | Notes |
|---|---|---|
| `programs.hyprland.enable` | `programs.niri.enable` | |
| `xdg-desktop-portal-hyprland` | `xdg-desktop-portal-gnome` | niri uses gnome portal for screencasting |
| `security.pam.services.hyprlock` | `security.pam.services.swaylock` | or hyprlock — both work |
| `wayland.windowManager.hyprland` (HM) | `programs.niri.settings` (niri-flake HM) | or raw KDL via `xdg.configFile` |
| `exec-once` | `spawn-at-startup` in config.kdl | |
| `$mod` variable | `Mod` is built-in to niri | |
| `bind` / `bindl` / `bindel` | `binds { }` with `allow-when-locked=true` | |
| `hyprland/workspaces` in Waybar | `niri/workspaces` | Waybar 0.11.0+ |
| `XDG_CURRENT_DESKTOP=Hyprland` | `XDG_CURRENT_DESKTOP=niri` | (auto-set by niri-session) |
| `hyprctl dispatch` | `niri msg action` | |
| `hyprctl clients` | `niri msg windows` | |
| workspace numbers 1–N | workspace numbers 1–N (but per-monitor) | slightly different mental model |
| dwindle layout | columns layout (built-in, always-on) | the core tiling model is different |
| `col.active_border` gradient | `focus-ring { active-gradient ... }` | Oklab/Oklch color support |
| `general.gaps_in/out` | `layout { gaps ... }` | |
| window rules via `windowrulev2` | `window-rule { match ... }` | similar concept, KDL syntax |

**Stays the same:**
- Waybar CSS styling and all non-workspace modules
- swayidle / swaylock / hyprlock configuration
- mako / dunst for notifications
- rofi or fuzzel for launching apps
- swaybg or wpaperd for wallpapers
- All environment variables except `XDG_CURRENT_DESKTOP`
- The greetd + tuigreet setup
- PipeWire, bluetooth, fonts — nothing changes at the system level

**What is genuinely different (not just remapping):**
- The tiling model. There are no numbered fixed workspaces in the Hyprland sense — niri's dynamic per-monitor workspaces take adjustment.
- No `layout = "dwindle"` concept. Windows go into columns; you split columns, not workspaces.
- No `pseudo` mode or `preserve_split`. The scrolling model eliminates the need for these.
- Touchpad gestures in niri use a different config block (`gestures { }`) and are for workspace/scroll navigation, not arbitrary keybind dispatch like Hyprland's gesture plugin.
- Config format is KDL, not the Hyprland-specific INI-like format. This is a small but real learning curve.
- No per-workspace persistent layout. Niri's layout is always the scrollable column model.

---

### Known Limitations and Rough Edges (as of early 2026)

- **No touchscreen gestures** — touchpad gestures work, touchscreen does not yet.
- **XWayland requires xwayland-satellite** as a separate process (since 25.08). It works well in practice but is an extra moving part.
- **No scratchpad built-in** — Hyprland has a special scratchpad workspace. Niri can approximate this with floating windows + IPC scripts, but it requires more work.
- **No per-workspace wallpaper** — wallpaper is set globally by an external tool.
- **No cursor warping** — Hyprland can warp the cursor to a new focused window. Niri does not.
- **No built-in blur/rounded corners as prominent** — niri has shadow support and gradient borders; blur is less prominent than Hyprland's (which is a big visual feature for many).
- **Config is KDL, not Nix** — if using nixpkgs's `programs.niri.enable` without niri-flake, you must manage the KDL file yourself (or use `xdg.configFile`). niri-flake's declarative Nix settings solve this but add a flake dependency.
- **Fullscreen idle inhibit bug** — fullscreen idle inhibition may not work correctly in browsers other than Firefox (issue #2114 was open as of early 2026).
- **No animation compositor effect equivalents** — Hyprland has very polished blur, vibrancy, etc. Niri's visual effects are simpler (borders, shadows, animations). This is by design — niri prioritizes correctness over visual flash.

---

## Part 2: Noctalia — Desktop Shell

### Clarification: Not a Terminal Shell

The name "Noctalia" might suggest a terminal/command shell (like fish, zsh, bash), but it is not. **Noctalia is a desktop shell for Wayland** — more comparable to GNOME Shell or KDE Plasma's visual layer than to fish.

If you were thinking of a different shell, see the "You Might Have Meant" section below.

---

### What is Noctalia?

Noctalia is "a beautiful, minimal desktop shell for Wayland built with Quickshell" (Quickshell is a Qt6/QML-based framework for building desktop interfaces). Its design philosophy is "quiet by design" — providing a complete-looking desktop that stays out of your way.

**Repo:** https://github.com/noctalia-dev/noctalia-shell
**Docs:** https://docs.noctalia.dev/

Noctalia is not a compositor, not a terminal emulator, and not a command-line shell. It is the **visual/interaction layer** that sits on top of your Wayland compositor.

---

### What Noctalia Provides

- Status bar / panel
- Application launcher
- Notification system (with history and Do Not Disturb)
- Lock screen
- Idle management (via swayidle integration)
- On-screen display (OSD) for volume/brightness changes
- Desktop widgets (clock, media player, calendar)
- Wallpaper management (with Wallhaven integration)
- Theming system (predefined color schemes + automatic color generation from wallpaper)
- Dock
- Multi-monitor support
- Plugin system (~100 community plugins as of 2026)

This overlaps heavily with what this config already handles piecemeal:

| This setup (piecemeal) | Noctalia equivalent |
|---|---|
| Waybar (bar) | Noctalia panel/bar |
| dunst (notifications) | Noctalia notifications |
| hyprlock (lock screen) | Noctalia lock screen |
| hypridle / swayidle (idle) | Noctalia idle management |
| rofi (launcher) | Noctalia app launcher |
| swaybg (wallpaper) | Noctalia wallpaper manager |
| custom waybar OSD | Noctalia OSD |

Noctalia's pitch is replacing all of these with one cohesive, themed system.

---

### Compositor Support

Noctalia explicitly supports:
- Niri
- Hyprland
- Sway
- Scroll
- Labwc
- MangoWC

This makes it an interesting option if you switch between compositors — one shell config works everywhere.

---

### NixOS Integration

Noctalia is not yet in nixpkgs. You use it via its own flake.

Add to `flake.nix` inputs:
```nix
noctalia.url = "github:noctalia-dev/noctalia-shell";
noctalia-qs.url = "github:noctalia-dev/noctalia-qs";
# The noctalia-qs input may be pulled automatically in recent versions
```

Nixpkgs unstable is required (Quickshell depends on recent Qt6 versions).

Binary cache to avoid local compilation:
```nix
nix.settings = {
  extra-substituters = [ "https://noctalia.cachix.org" ];
  extra-trusted-public-keys = [
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
  ];
};
```

Install (without Home Manager):
```nix
environment.systemPackages = [
  inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
];
```

With Home Manager:
```nix
imports = [ inputs.noctalia.homeModules.default ];

programs.noctalia-shell = {
  enable = true;
  settings = {
    # colors, plugins, wallpapers, keybinds
  };
};
```

Home Manager converts the Nix settings to JSON files in `~/.config/noctalia/`, and a systemd user service restarts when config changes.

System prerequisites:
```nix
networking.networkmanager.enable = true;  # for wifi widget
hardware.bluetooth.enable = true;          # for bluetooth widget
services.power-profiles-daemon.enable = true;  # or tuned
services.upower.enable = true;             # for battery widget
```

Run with: `noctalia-shell` (or configured as `spawn-at-startup` in niri config).

---

### Relationship to This Setup

Noctalia would be a full replacement for: Waybar + dunst + hyprlock (as lock UI) + hypridle + rofi + swaybg. It provides a more integrated, opinionated experience.

Trade-offs:
- **Pro:** One coherent shell vs six separate tools. Automatic theming from wallpaper. Active development.
- **Pro:** Works with both Hyprland and niri, so you could use it on either without rebuildling the shell layer.
- **Con:** Not in nixpkgs — requires a flake dependency. Pre-built binaries via Cachix mitigate compile time.
- **Con:** Less configuration flexibility than hand-tuned Waybar CSS + separate tools.
- **Con:** Depends on Qt6/Quickshell — different dependency stack than the GTK-oriented existing setup.
- **Con:** Relatively new project (early 2026). The ecosystem is younger than the individual tools it replaces.

---

### You Might Have Meant: Fish Shell Alternatives

If "noctalia" was a misremembering or misspelling, here are the commonly discussed fish-adjacent shells:

| Name | What it is |
|---|---|
| **fish** | The current shell in use. Friendly interactive shell with auto-complete and syntax highlighting. |
| **nushell** (`nu`) | Structured data shell — pipelines output objects/tables, not text. Powerful for data manipulation. Very different paradigm from fish/bash. |
| **navi** | Not a shell — a cheatsheet/snippet tool that integrates with any shell. |
| **elvish** | Another structured shell with functional programming influences. Less popular than nushell. |
| **xonsh** | Python-based shell. Embeds Python directly. |
| **oils** (formerly Oil Shell) | POSIX-compatible shell with a cleaner superset language (YSH). |

If you were researching **nushell** specifically: it is available in nixpkgs as `nushell`, and Home Manager has `programs.nushell`. It pairs well with a fish interactive experience — some people use nushell as their interactive shell while keeping bash/fish for scripts. It has a steeper learning curve than fish because its data model is fundamentally different.

---

## Summary Comparison

| Topic | Niri vs Hyprland | Noctalia vs piecemeal setup |
|---|---|---|
| Mental model shift | High — scrolling strip vs discrete workspaces | Medium — one system vs six tools |
| Config format change | KDL instead of Hyprland syntax | Nix (via HM module) + JSON |
| Waybar reuse | Yes, with minor module name change | No — Noctalia replaces Waybar |
| NixOS integration | nixpkgs or niri-flake | External flake + Cachix |
| Maturity | Stable daily driver since 2024 | Active but younger (2025+) |
| Biggest win | More natural workflow for many apps open at once | Coherent theming and integration |
| Biggest risk | Different tiling model requires workflow relearning | External flake dependency, less config control |
| Try without committing | Yes — run as nested window with `niri` | Yes — run `noctalia-shell` from Hyprland |

---

## Sources

- [niri GitHub (niri-wm)](https://github.com/niri-wm/niri)
- [niri NixOS Wiki](https://wiki.nixos.org/wiki/Niri)
- [niri-flake (sodiboo)](https://github.com/sodiboo/niri-flake)
- [niri ArchWiki](https://wiki.archlinux.org/title/Niri)
- [niri Getting Started](https://niri-wm.github.io/niri/Getting-Started.html)
- [niri Integrating wiki](https://github.com/niri-wm/niri/wiki/Integrating-niri)
- [niri v25.01 release notes](https://github.com/niri-wm/niri/discussions/956)
- [niri v25.05 release notes](https://github.com/niri-wm/niri/discussions/1589)
- [Day-to-day niri workflows (Nick Janetakis)](https://nickjanetakis.com/blog/day-to-day-window-management-workflows-and-why-i-picked-niri)
- [Noctalia docs](https://docs.noctalia.dev/)
- [Noctalia NixOS guide](https://docs.noctalia.dev/getting-started/nixos/)
- [Noctalia GitHub](https://github.com/noctalia-dev/noctalia-shell)
- [Configure Swayidle for Niri and Noctalia (Andrew McCall)](https://andrew-mccall.com/blog/2026/01/configure-swayidle-for-niri-and-noctalia-quickshell/)
- [Niri xwayland-satellite Phoronix article](https://www.phoronix.com/news/Niri-25.08-Released)
