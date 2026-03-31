# Bearing Delegation — nixos-config
_The Bearing communicates with this project through this file._
_Last updated: 2026-03-31_

---

## Pending
_Tasks delegated by The Bearing, not yet started._

> **Next up — do these first, in order:**
> 1. diagnose and fix the nixos mcp error.
> 2. Bearing refactor

- [ ] **[pri 1] Add Korean language support.** Add Korean input method support to the NixOS config (likely fcitx5 or ibus with Korean IME). Goal: enable Korean character input system-wide, in preparation for Hangul keyboard stickers and switching from romanized input. Delegated 2026-03-31.

- [x] **[NEXT — pri 1] Cold-start efficiency audit.** — 2026-03-29
  - Created `docs/runbooks/add-module.md` — system and home module checklist, gotchas (unfree, foot vs kitty, parts/nixos.nix wiring), skeletons
  - Created `docs/runbooks/add-host.md` — new host checklist, desktop vs server distinction, stateVersion gotchas, VM notes
  - Created `docs/runbooks/debug-build.md` — maps common error types (attribute missing, infinite recursion, type errors, HM activation failures) to causes and commands
  - Updated `CLAUDE.md` with explicit routing directives: "before doing X, read docs/runbooks/Y.md"
  - No repeating tasks left without a runbook. "Updating flake inputs" is too simple to warrant one (two commands, already in Key Commands).

- [x] **[NEXT — pri 2] Architecture question: multi-host module sharing.** — 2026-03-29
  - Closed. The line of reasoning pursued was not what was intended. Work product archived to `docs/archive/multi-host-sharing.md` and is of no value. No conclusions to carry forward.
- [ ] **Wayland session management — assess config impact.** The xdg-session-management protocol was merged March 23, 2026, after a 6-year wait. It enables system-wide window state/position restore across crashes and reboots — similar to browser session restoration but compositor-level. KWin already implemented it; broader adoption expected. Article: https://itsfoss.com/news/wayland-session-management/ — read it for full context. Question to answer: does this affect the current compositor setup (niri/Hyprland)? Is there config to enable, a module option to add, or is it purely a compositor-side change with no NixOS action needed yet? Write up a brief assessment and drop a note back here.

- [ ] **Refactor bearing.nix into a thin import wrapper.** Repo confirmed created: `git@github.com:robie1373/the-bearing.git`. bearing.nix should only: add it as a flake input, enable the module, and set user config (ntfy topic, schedule, workDir, terminal). All scripts, templates, and module logic move to the external repo. See architecture notes below.

## In Progress

- [ ] —

## Completed

- [x] **Fix bearing-briefing stdin pipe** — 2026-03-24
  - Changed `$(cat template)` to `cat template | claude --print` in `bearingBriefing` derivation
  - Build verified clean

- [x] **Fix bearing-briefing unattended SSH auth** — 2026-03-24
  - Added `Environment = [ "SSH_AUTH_SOCK=" ]` to bearing-briefing systemd service
  - Prevents 1Password SSH agent prompts when timer fires unattended at 06:30
  - Build verified clean

- [x] **Haiku subagent delegation instructions added to CLAUDE.md** — 2026-03-24
  - Added "Model use — subagent delegation" section after the project description
  - Lists Haiku candidates specific to this project: option syntax searches, reading/summarising modules and guides, grepping patterns, writing guide files, BEARING.md updates
  - Lists Sonnet-only tasks: cross-module Nix reasoning, build failures, architecture decisions, hardware/security config
  - Includes one-line Agent tool invocation example with `model="haiku"`

- [x] **Bearing Nix home-manager module** — 2026-03-24
  - `modules/home/bearing.nix` created with full `myHome.bearing` options
  - Scripts (`bearing-notify`, `bearing-ntfy`, `bearing-checkin`, `bearing-open`) defined as Nix derivations
  - Systemd user timers + services for morning/checkin/afternoon replace imperative units
  - Enabled in `hosts/flipper/home.nix`
  - Build verified clean

- [x] **ntfy topic moved to 1Password** — 2026-03-24
  - `bearing-ntfy` fetches topic at runtime from `~/work/.ntfy-topic` (populated via `op read`)
  - 1Password item created: vault `devops`, title `temp ntfy topic bearing`, field `password`
  - `~/work/.ntfy-topic` populated

- [x] **bearing-activity script + 06:30 timer** — 2026-03-25
  - `bearingActivity` derivation added to `bearing.nix`
  - Reads `~/work/templates/activity-gather.md` via stdin pipe; runs `claude --print --allowedTools "Bash,Write"`
  - Service + timer fire at `cfg.schedule.briefing` (06:30), parallel with `bearing-briefing`
  - `SSH_AUTH_SOCK=` cleared in service environment (git log is local, no 1Password needed)
  - **Requires:** `~/work/templates/activity-gather.md` to exist before 06:30 fires

- [x] **bearing-open type-aware + `bearing` command + Super+B keybind** — 2026-03-24
  - `bearing-open` now validates `$1` with a case statement — known types (morning/checkin/afternoon/briefing/bearing) pass through; unknown args (e.g. dunst's appname) fall back to "bearing"
  - `bearing` user command added to PATH — `exec claude bearing` in current terminal, terminal closes on exit
  - `Super+B` keybind added to Hyprland (`desktop-hyprland.nix`) — opens foot with `claude bearing` in `~/work`
  - **Note on services:** services still call `bearing-checkin` (preserving desktop + phone notifications). BEARING.md said to update ExecStart to call `bearing-open`, but that would remove notifications. If the intent is to open a terminal session directly from the timer (no notification), revise.

- [x] **bearing-briefing timer** — 2026-03-24
  - `bearingBriefing` script added: `claude --print --allowedTools "WebSearch,WebFetch,Write"` with template prompt
  - `schedule.briefing` option added (default `06:30`)
  - Service + timer added, fires before morning check-in
  - `bearing-briefing` added to PATH

- [x] **Dunst click-to-open fix** — 2026-03-24
  - `global.mouse_left_click = "do_action, close_notification"` added
  - `bearing` dunst rule: `appname = "The Bearing"`, `script = ${bearingOpen}` (store path)
  - `bearing-notify` simplified to non-blocking `dunstify` — no `-A` flag, no hanging service
  - Both fixes live in `modules/home/bearing.nix` alongside the scripts

---

## Notes from The Bearing

**Inter-project coordination — homeLab edits to nixos-config (2026-03-25):**
homeLab is working on NixOS-related infrastructure tasks and will be making additions or suggestions to configuration that ultimately lives in nixos-config. homeLab has been instructed to annotate those changes with comments explaining intent and context. nixos-config has full ownership over the final disposition of that config — homeLab's comments are input, not decisions. When you encounter commented additions from homeLab, review them, understand the goal, and produce configuration that actually works and fits the existing nixos-config architecture. You are not obligated to use homeLab's exact approach — only to accomplish the stated goal correctly.

---

## Notes to The Bearing
_Anything this project's Claude session wants to report back._

**Cold-start audit complete (2026-03-29).** Three runbooks written in `docs/runbooks/`: `add-module.md`, `add-host.md`, `debug-build.md`. CLAUDE.md updated with routing. "Flake input update" was the only repeating task left without a dedicated runbook — it's two commands and already in CLAUDE.md Key Commands, so no separate doc was warranted.


**Services call bearing-checkin (desktop + phone notifications), not bearing-open (terminal).** If the intent changes to open a terminal directly from the timer instead of notifying, revise ExecStart in the three check-in services in `modules/home/bearing.nix`.

---

## Design Notes — Bearing Nix Package

**Goal:** Convert the imperatively configured Bearing into a Nix flake + home-manager module,
managed declaratively via nixos-config. Host logic on GitHub (public or private).

**Separation of concerns:**
- **Logic** (scripts, templates) → GitHub repo, safe to publish
- **Configuration** (ntfy topic, schedule times, terminal, paths) → home-manager module options, stays in nixos-config
- **Data** (DOMAINS.md, logs, OBLIGATIONS.md, DELEGATIONS.md) → ~/work/, never leaves the machine

**Resolved:** ntfy topic is no longer hardcoded — it is fetched at runtime from 1Password via `op read`. The `ntfy.opRef` option holds the `op://` reference; the topic string itself never enters the Nix store.

**Module options to design (roughly):**
```nix
programs.bearing = {
  enable = true;
  workDir = "~/work";
  terminal = "foot";
  ntfy = {
    server = "https://ntfy.sh";
    topic = "bearing-zj7bx0f7i15ifo0c";  # kept in nixos-config, not the flake
  };
  schedule = {
    morning = "08:00";
    checkin = "13:00";
    afternoon = "16:30";
  };
};
```

**Module responsibilities:**
- Install bearing scripts to PATH
- Write systemd user timer + service units
- Generate bearing-ntfy config with topic injected at build time
- Optionally install templates to workDir on first run (not overwrite)

**GitHub repo decision:** private is safer for now (avoids accidentally leaking
any config that bleeds in). Can be made public once separation is clean and reviewed.

**Current imperative state to replace:**
- ~/.config/systemd/user/bearing-{morning,checkin,afternoon}.{timer,service}
- ~/work/scripts/ (bearing-notify, bearing-ntfy, bearing-checkin)
- These can be deleted once the Nix module takes over

---

## Fix: bearing-briefing script invocation

The `$(cat template)` form used in bearing.nix fails — Claude Code's `--print` flag doesn't accept prompt arguments via `$()` expansion in that context. The working form is stdin pipe:

```bash
cat ~/work/templates/briefing-gather.md | claude --print --allowedTools "WebSearch,WebFetch,Write"
```

Update the `bearingBriefing` derivation in `bearing.nix` accordingly.

---

## Fix: bearing-briefing unattended SSH auth

**Problem:** Every Claude Code invocation triggers a `git` command at startup, which contacts the 1Password SSH agent and raises an auth prompt. In an unattended context (06:30 timer, no user present) this will either hang or fail silently — the briefing won't run.

**Root cause:** Claude Code probes git context on startup. The SSH agent (via 1Password) intercepts even passive git queries and prompts for key authorization.

**Fix for the briefing service specifically:** Clear `SSH_AUTH_SOCK` in the systemd service environment so 1Password is never consulted. The briefing agent only needs `WebSearch`, `WebFetch`, and `Write` — no SSH required.

In `bearing.nix`, add to the `bearing-briefing` service:
```nix
systemd.user.services.bearing-briefing = {
  Service = {
    Environment = [
      "SSH_AUTH_SOCK="   # prevent 1Password SSH prompts in unattended context
    ];
    # ... rest of service config
  };
};
```

**Broader issue:** The interactive 1Password SSH prompt on every `claude` invocation is a known issue tracked separately in nixos-config. That fix is out of scope here — just unblock the unattended briefing service for now.

---

## Architecture Note

bearing.nix is currently monolithic — scripts, templates, module logic, and config all live here. This happened organically during initial development. The intended end state is:
- **External flake** (`the-bearing` GitHub repo): scripts, module definition, templates
- **bearing.nix here**: thin wrapper — `inputs.the-bearing.homeManagerModules.default` + user config options only

Refactoring is deferred until the external repo exists. For now, continue adding to bearing.nix as needed. When the repo is created, bearing.nix will be gutted and replaced.

---

## Briefing Pre-gather Agent (06:30 timer)

**Goal:** Gather weather, fishing reports, motorsports schedule, and today-in-history before the morning bearing so Claude doesn't fetch live during the session.

**New service + timer in `modules/home/bearing.nix`:**

```nix
systemd.user.services.bearing-briefing = {
  Unit = {
    Description = "The Bearing — morning briefing pre-gather";
    After = [ "network-online.target" ];
  };
  Service = {
    Type = "oneshot";
    ExecStart = "${bearingBriefing}/bin/bearing-briefing";
  };
};

systemd.user.timers.bearing-briefing = {
  Unit.Description = "The Bearing — morning briefing timer";
  Timer = {
    OnCalendar = "Mon-Sun 06:30";
    Persistent = true;
  };
  Install.WantedBy = [ "timers.target" ];
};
```

**`bearing-briefing` script:**
```bash
#!/usr/bin/env bash
# Run claude non-interactively to gather morning briefing
# Output goes to ~/work/briefing/YYYY-MM-DD.md (claude writes the file itself)
cd ~/work
claude --print \
  --allowedTools "WebSearch,WebFetch,Write" \
  "$(cat ~/work/templates/briefing-gather.md)"
```

**Permissions note:** Claude Code needs WebSearch, WebFetch, and Write allowed in non-interactive/headless mode. Check `~/.claude/settings.json` — may need to add these to `allowedTools` for the `~/work` project, or use `--allowedTools` flag on the command line. Test manually first:
```bash
cd ~/work && claude --print --allowedTools "WebSearch,WebFetch,Write" "$(cat ~/work/templates/briefing-gather.md)"
```

**New script derivation** in bearing.nix:
```nix
bearingBriefing = pkgs.writeShellScriptBin "bearing-briefing" ''
  cd ${cfg.workDir}
  ${pkgs.claude-code}/bin/claude --print \
    --allowedTools "WebSearch,WebFetch,Write" \
    "$(cat ${cfg.workDir}/templates/briefing-gather.md)"
'';
```
Add to `home.packages`.

---

## Ad-hoc Bearing Command + Keybinding

**Problem:** `bearing-open` currently runs `claude` with no initial message, so Claude opens a blank session. Claude needs an initial prompt to trigger the bearing interaction from CLAUDE.md.

**Fix 1 — Make bearing-open type-aware:**

`bearingOpen` should accept a TYPE argument and pass it to claude:
```bash
#!/usr/bin/env bash
TYPE="${1:-bearing}"
cd ~/work && exec claude "$TYPE"
```

Each systemd service should call it with the right type:
- `bearing-morning.service` → `bearing-open morning`
- `bearing-checkin.service` → `bearing-open checkin`
- `bearing-afternoon.service` → `bearing-open afternoon`

Update `ExecStart` in each service in `modules/home/bearing.nix` accordingly.

**Fix 2 — `bearing` user command** (in PATH):
For ad-hoc use from any terminal — runs claude in the current shell:
```bash
#!/usr/bin/env bash
cd ~/work && exec claude "bearing"
```
Add as a new `pkgs.writeShellScriptBin "bearing"` in bearing.nix, added to `home.packages`.

**Fix 3 — Hyprland keybinding** (Super+B):
Opens a new foot terminal with a bearing session — for keybinding and dunst click:
```nix
"$mod, B, exec, ${bearingOpen} bearing"
```
Add to the `bind` list in `desktop-hyprland.nix`. The `bearingOpen` script path is a nix store path — either expose it from bearing.nix or inline the command:
```nix
"$mod, B, exec, foot -- bash -c 'cd ~/work && claude bearing; exec bash'"
```

---

## Dunst Fix — Click-to-Open for Bearing Notifications

**Problem:** Two bugs in current imperative setup:
1. `mouse_left_click` defaults to `close_notification` — clicking a Bearing notification just dismisses it
2. `bearing-notify` uses blocking `dunstify -A` which hangs the systemd service indefinitely

**Fix required in `services.dunst.settings` (home-manager):**

```nix
services.dunst.settings = {
  global = {
    # ... existing settings ...
    mouse_left_click = "do_action, close_notification";
  };

  bearing = {
    appname = "The Bearing";
    script = "/path/to/bearing-open";  # path will be nix-store path once packaged
  };
};
```

**`bearing-open` script** (to be generated by the Nix module):
```bash
#!/usr/bin/env bash
foot -- bash -c 'cd ~/work && claude; exec bash'
```

**In the Nix module**, `bearing-open` should be a `pkgs.writeShellScript` so its store
path can be referenced directly in the dunst rule. The `bearing-notify` script should be
simplified to a plain non-blocking `dunstify` call — no `-A` flag, no blocking.
Click handling is entirely dunst's responsibility via the rule above.

---

## Git Activity Agent (06:30 timer)

**Goal:** Read git logs across all active project repos since yesterday 00:00 (full previous day), summarize in plain English, write to `~/work/briefing/YYYY-MM-DD-activity.md`. The morning bearing reads this file to surface yesterday's accomplishments motivationally.

**Runs in parallel with `bearing-briefing`** — same 06:30 timer window, independent service.

**New script `bearing-activity`:**
```bash
#!/usr/bin/env bash
# Runs claude non-interactively to summarize yesterday's git activity
# Output goes to ~/work/briefing/YYYY-MM-DD-activity.md
cd ~/work
cat ~/work/templates/activity-gather.md \
  | ${pkgs.claude-code}/bin/claude --print \
      --allowedTools "Bash,Write"
```

Note: uses `Bash` (for git log) and `Write` — no network tools needed. `SSH_AUTH_SOCK` should be cleared as with `bearing-briefing` since git log is local-only and we don't want 1Password prompts.

**New script derivation in bearing.nix:**
```nix
bearingActivity = pkgs.writeShellScriptBin "bearing-activity" ''
  mkdir -p ${cfg.workDir}/briefing
  cd ${cfg.workDir}
  cat ${cfg.workDir}/templates/activity-gather.md \
    | ${pkgs.claude-code}/bin/claude --print \
        --allowedTools "Bash,Write"
'';
```
Add to `home.packages`.

**New service + timer:**
```nix
systemd.user.services.bearing-activity = {
  Unit = {
    Description = "The Bearing — git activity pre-gather";
    After = [ "default.target" ];
  };
  Service = {
    Type = "oneshot";
    ExecStart = "${bearingActivity}/bin/bearing-activity";
    Environment = [ "SSH_AUTH_SOCK=" ];
  };
};
systemd.user.timers.bearing-activity = {
  Unit.Description = "The Bearing — git activity pre-gather timer";
  Timer = {
    OnCalendar = "Mon-Sun ${cfg.schedule.briefing}";
    Persistent = true;
  };
  Install.WantedBy = [ "timers.target" ];
};
```

**`schedule.briefing`** is already a module option (default `06:30`) — reuse it so both agents fire at the same time.

The prompt template lives at `~/work/templates/activity-gather.md` — already written by The Bearing.

