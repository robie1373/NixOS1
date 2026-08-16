{ pkgs, ... }:
# The Bearing — life-tracking assistant scripts + maintenance timers.
# System-level port of modules/_home/bearing.nix (HM removal Phase B).
#
# Ported fresh on main; the poisoned-chain notes (ledger nixos-niri.md) applied:
#   - dunstify → notify-send: noctalia is the notification daemon; dunst was
#     enabled by the HM module but not even running. The dunst click-to-open
#     rule (bearing-open) died with it — Super+B and the `bearing` command are
#     the entry points.
#   - workDir hardcoded to /home/robie/work — no config.home.* at system level.
#
# Only flipper imports this. fivenix's HM import of bearing.nix was a no-op
# (myHome.bearing.enable was never set there).
let
  workDir    = "/home/robie/work";
  # LAN endpoint, not the Tailscale one (2026-08-02). Plain HTTP by design — no cert
  # exists for home.lab and the topic name is the secret, not the payload. Publishers
  # must not depend on Tailscale; see ledger2/ntfy.md and ledger2/tailscale-removal.md.
  ntfyServer = "http://ntfy.home.lab";
  lintTime   = "16:00";  # daily Ledger lint (headless, ntfy summary)
  doctorTime = "15:45";  # daily self-check — deliberately before the lint
  ingestTime = "02:00";  # nightly ~/raw/ ingestion
  promptTime = "Sun 09:14";  # weekly notebook prompt

  # bearing: ad-hoc user command. Runs a bearing session in the current terminal.
  # exec replaces the shell — terminal closes when the session ends.
  bearingCmd = pkgs.writeShellScriptBin "bearing" ''
    cd ${workDir} && exec claude bearing
  '';

  # bearing-notify: sends a non-blocking desktop notification (noctalia renders it).
  bearingNotify = pkgs.writeShellScriptBin "bearing-notify" ''
    TYPE="''${1:-checkin}"
    case "$TYPE" in
      morning)
        TITLE="Morning Bearing"
        BODY="Time to take a bearing and frame your day."
        URGENCY="normal"
        ;;
      checkin)
        TITLE="Bearing Check-in"
        BODY="How's it going? Worth a quick recalibration."
        URGENCY="low"
        ;;
      custom)
        TITLE="''${2:-The Bearing}"
        BODY="''${3:-Check in.}"
        URGENCY="''${4:-normal}"
        ;;
      *)
        TITLE="The Bearing"
        BODY="$*"
        URGENCY="normal"
        ;;
    esac
    ${pkgs.libnotify}/bin/notify-send \
      -a "The Bearing" \
      -u "$URGENCY" \
      -t 0 \
      "$TITLE" "$BODY"
  '';

  # bearing-checkin: manual notification command (no longer timer-driven as of the
  # 2026-06-25 pull-model switch). Fires desktop and phone (ntfy) notifications.
  # ntfy topic is read from ~/work/.ntfy-topic at runtime — populate with:
  #   op read 'op://devops/temp ntfy topic bearing/password' > ~/work/.ntfy-topic
  # Silently skips ntfy if the file is missing.
  bearingCheckin = pkgs.writeShellScriptBin "bearing-checkin" ''
    TYPE="''${1:-checkin}"
    ${bearingNotify}/bin/bearing-notify "$TYPE" &
    TOPIC="$(cat ${workDir}/.ntfy-topic 2>/dev/null)"
    if [ -n "$TOPIC" ]; then
      case "$TYPE" in
        morning)
          TITLE="Morning Bearing"; MSG="Time to take a bearing."; PRI="default"; TAGS="compass" ;;
        checkin)
          TITLE="Check-in"; MSG="Worth a quick recalibration."; PRI="low"; TAGS="clock" ;;
        *)
          TITLE="The Bearing"; MSG="Check in."; PRI="default"; TAGS="bell" ;;
      esac
      ${pkgs.curl}/bin/curl -s \
        -H "Title: $TITLE" \
        -H "Priority: $PRI" \
        -H "Tags: $TAGS" \
        -d "$MSG" \
        "${ntfyServer}/$TOPIC"
    fi
    wait
  '';

  # bearing-briefing: runs claude non-interactively to pre-gather morning context.
  # Substitutes {{RECENT_TOPICS}} in the template with section headers from the last
  # 3 briefing files so the agent avoids picking the same topics two days running.
  # Claude writes output to ~/work/briefing/YYYY-MM-DD.md per template instructions.
  # Requires templates/briefing-gather.md to exist in workDir.
  bearingBriefing = pkgs.writeShellScriptBin "bearing-briefing" ''
    mkdir -p ${workDir}/briefing
    cd ${workDir}
    ${pkgs.python3}/bin/python3 -c "
import os, sys
briefing_dir = '${workDir}/briefing'
files = sorted(
    f for f in os.listdir(briefing_dir)
    if f.endswith('.md') and 'activity' not in f
)[-3:]
topics = []
for fn in files:
    with open(os.path.join(briefing_dir, fn)) as f:
        for line in f:
            if line.startswith('## '):
                t = line.strip().lstrip('# ').strip()
                if t and t not in topics:
                    topics.append(t)
recent = '\n'.join('- ' + t for t in topics) or '(none yet — all topics are fair game)'
template = open('${workDir}/templates/briefing-gather.md').read()
sys.stdout.write(template.replace('{{RECENT_TOPICS}}', recent))
" | ${pkgs.claude-code}/bin/claude --print \
        --allowedTools "WebSearch,WebFetch,Write"
  '';

  # bearing-activity: runs claude non-interactively to summarise yesterday's git activity.
  # Reads prompt from ~/work/templates/activity-gather.md via stdin pipe.
  # Claude writes output to ~/work/briefing/YYYY-MM-DD-activity.md per template instructions.
  # No network tools needed — git log is local. SSH_AUTH_SOCK cleared in service.
  bearingActivity = pkgs.writeShellScriptBin "bearing-activity" ''
    mkdir -p ${workDir}/briefing
    cd ${workDir}
    cat ${workDir}/templates/activity-gather.md \
      | ${pkgs.claude-code}/bin/claude --print \
          --allowedTools "Bash,Write"
  '';

  # bearing-lint: runs claude non-interactively to lint the Ledger.
  # Substitutes {{LINT_FILE}} in the template with today's dated log path.
  # Claude writes detailed findings to ~/work/lint/YYYY-MM-DD.md and prints
  # a one-line summary as its final stdout line, which is sent via ntfy.
  # Capped at 10 minutes via timeout.
  bearingLint = pkgs.writeShellScriptBin "bearing-lint" ''
    mkdir -p ${workDir}/lint
    TODAY=$(date +%Y-%m-%d)
    LINT_FILE="${workDir}/lint/$TODAY.md"

    PROMPT=$(sed "s|{{LINT_FILE}}|$LINT_FILE|g" ${workDir}/templates/ledger-lint.md)
    SUMMARY=$(echo "$PROMPT" \
      | timeout 600 ${pkgs.claude-code}/bin/claude --print \
          --allowedTools "Bash,Read,Glob,Grep,Write" 2>/dev/null)
    EXIT=$?

    # A queued fix is one the lint FOUND but could not APPLY (the job is
    # deliberately read-only on ~/ledger2 — it has no Edit tool). One such report
    # is routine. The same queue recurring is the actual alarm: the Technitium
    # reconciliation was queued by EIGHT consecutive passes (2026-07-28 → 08-16)
    # and applied by none, while the drift spread from 8 pages to 11. Every one of
    # those notifications was honest and none of them said "again". This counts the
    # streak so a standing backlog escalates itself. See ~/ledger2/journal/2026-08-16.md.
    #
    # Precisely: this counts consecutive passes whose queue was non-empty, NOT
    # consecutive passes queueing the SAME fix. A new finding the day after an old
    # one is cleared still extends the count. That is the intended reading anyway —
    # a persistently non-empty queue means fixes are not being applied, whatever
    # they are — but do not read the number as "this one item is N passes old".
    has_queue() {
      awk '/^## Queued fixes/{f=1;next} /^## /{f=0} f' "$1" \
        | sed 's/^[[:space:]]*//' | grep -v '^$' \
        | grep -qivE '^-?[[:space:]]*(none|none / applied directly|\[.*\])$'
    }
    STREAK=0
    for f in $(ls -r ${workDir}/lint/*.md 2>/dev/null); do
      if has_queue "$f"; then STREAK=$((STREAK+1)); else break; fi
    done

    TOPIC="$(cat ${workDir}/.ntfy-topic 2>/dev/null)"
    if [ -n "$TOPIC" ]; then
      if [ "$EXIT" -eq 124 ]; then
        MSG="Lint timed out after 10 minutes."; PRI="low"; TAGS="warning"
      else
        MSG=$(printf "%s" "$SUMMARY" | grep -v '^[[:space:]]*$' | tail -1)
        [ -z "$MSG" ] && MSG="Lint complete — see ~/work/lint/$TODAY.md"
        PRI="low"; TAGS="books"
        if [ "$STREAK" -ge 2 ]; then
          MSG="[$STREAK passes queued, UNAPPLIED] $MSG"
          PRI="default"; TAGS="warning"
        fi
      fi
      ${pkgs.curl}/bin/curl -s \
        -H "Title: Ledger lint" \
        -H "Priority: $PRI" \
        -H "Tags: $TAGS" \
        -d "$MSG" \
        "${ntfyServer}/$TOPIC"
    fi
  '';

  # bearing-doctor: health check for The Bearing's OWN state (2026-08-09).
  #
  # Built after a single day surfaced four independent instances of the same
  # failure: the Trust Vector protocol had been off for four sessions, the memory
  # dir contradicted CLAUDE.md, briefings had been dead for ten days, and
  # me/interests.md had been wrong about two domains for six weeks. Each was
  # caught by accident. The lab has observ; the assistant had nothing.
  #
  # DELIBERATELY NOT a claude --print call, unlike bearing-lint. This checks
  # Claude's own housekeeping, so a degraded session would produce a degraded
  # check — the exact bug it exists to catch. Pure python, offline, deterministic.
  #
  # The script itself lives in ~/work/bin/ (versioned in the work repo) rather
  # than inline here, so its checks can be edited without a rebuild — same
  # pattern as the templates/ files the other jobs read at runtime.
  #
  # ntfy on FINDINGS ONLY — a clean run is silent, per the standing rule that
  # success goes to the Bearing rather than a notification. Warnings notify as
  # well as failures: everything this was built for was slow rot (a six-week-stale
  # interests.md, ten days of dead briefings), so silent warnings would reproduce
  # the bug. Severity rides in the message and the ntfy priority, not in whether
  # Robie hears about it at all.
  bearingDoctor = pkgs.writeShellScriptBin "bearing-doctor" ''
    REPORT=$(${pkgs.python3}/bin/python3 ${workDir}/bin/bearing-doctor 2>&1)
    EXIT=$?

    printf "%s\n" "$REPORT"

    # Exit 0 = clean, 1 = findings, anything else = the checker itself broke.
    [ "$EXIT" -eq 0 ] && exit 0

    TOPIC="$(cat ${workDir}/.ntfy-topic 2>/dev/null)"
    if [ -n "$TOPIC" ]; then
      if [ "$EXIT" -eq 1 ]; then
        MSG=$(printf "%s" "$REPORT" | grep -v '^[[:space:]]*$' | tail -1)
        PRI="default"; TAGS="stethoscope"
      else
        MSG="bearing-doctor itself failed (exit $EXIT) — the health check is blind."
        PRI="high"; TAGS="rotating_light"
      fi
      ${pkgs.curl}/bin/curl -s \
        -H "Title: Bearing doctor" \
        -H "Priority: $PRI" \
        -H "Tags: $TAGS" \
        -d "$MSG" \
        "${ntfyServer}/$TOPIC"
    fi
    exit "$EXIT"
  '';

  # bearing-ingest: runs claude non-interactively to ingest new files from ~/raw/.
  # Tracks processed files in ~/work/.ingest-manifest to avoid re-processing.
  # For each unprocessed .md file, pipes the ingest template + file contents to
  # claude --print. Sends an ntfy summary when new files are processed.
  # Capped at 3 minutes per file via timeout.
  bearingIngest = pkgs.writeShellScriptBin "bearing-ingest" ''
    MANIFEST="${workDir}/.ingest-manifest"
    RAW_DIR="$HOME/raw"
    touch "$MANIFEST"
    NEW_COUNT=0
    LOG_LINES=""

    while IFS= read -r f; do
      if grep -qxF "$f" "$MANIFEST"; then
        continue
      fi
      rel="''${f#$RAW_DIR/}"
      SOURCE_TYPE="''${rel%%/*}"
      CONTENTS=$(cat "$f" 2>/dev/null) || continue
      PROMPT=$(sed \
        -e "s|{{SOURCE_FILE}}|$f|g" \
        -e "s|{{SOURCE_TYPE}}|$SOURCE_TYPE|g" \
        "${workDir}/templates/ledger-ingest.md")
      RESULT=$(printf '%s\n\n%s' "$PROMPT" "$CONTENTS" \
        | timeout 180 ${pkgs.claude-code}/bin/claude --print \
            --allowedTools "Bash,Read,Write" 2>/dev/null)
      printf '%s\n' "$f" >> "$MANIFEST"
      LAST_LINE=$(printf '%s' "$RESULT" | grep -v '^[[:space:]]*$' | tail -1)
      LOG_LINES="''${LOG_LINES}''${LAST_LINE}\n"
      NEW_COUNT=$((NEW_COUNT + 1))
    done < <(find "$RAW_DIR" -name "*.md" -not -path "*/.obsidian/*" | sort)

    TOPIC="$(cat ${workDir}/.ntfy-topic 2>/dev/null)"
    if [ "$NEW_COUNT" -gt 0 ] && [ -n "$TOPIC" ]; then
      MSG="Ingested $NEW_COUNT new file(s) into the Ledger."
      ${pkgs.curl}/bin/curl -s \
        -H "Title: Ledger ingestion" \
        -H "Priority: low" \
        -H "Tags: inbox_tray" \
        -d "$MSG" \
        "${ntfyServer}/$TOPIC"
    fi
  '';

  # bearing-status: offline status card — no AI, no network.
  # Reads OBLIGATIONS.md and DELEGATIONS.md and prints a compact summary to stdout.
  bearingStatus = pkgs.writeShellScriptBin "bearing-status" ''
    TODAY=$(date +%Y-%m-%d)
    TOMORROW=$(date -d "tomorrow" +%Y-%m-%d)
    WORK="${workDir}"

    printf "══════════════════════════════════════\n"
    printf "  %s\n" "$(date '+%A, %B %-d %Y')"
    printf "══════════════════════════════════════\n"

    # ── Obligations (today/tomorrow from ## Upcoming) ─────────────────────
    printf "\n▸ OBLIGATIONS\n"
    OBL=$(awk -F'|' -v today="$TODAY" -v tom="$TOMORROW" '
      /^## Upcoming/  { sect=1; next }
      /^## /          { sect=0 }
      sect && /^\| *[0-9]{4}-/ {
        gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $4)
        if ($2==today || $2==tom)
          printf "  [%s %s] %s\n", ($2==today?"today":"tomorrow"), $3, $4
      }
    ' "$WORK/OBLIGATIONS.md" 2>/dev/null)
    [ -n "$OBL" ] && printf "%s\n" "$OBL" || printf "  (none today or tomorrow)\n"

    # ── Todos (from ## Todos — any row with a due date) ───────────────────
    printf "\n▸ TODOS\n"
    TODOS=$(awk -F'|' '
      /^## Todos/  { sect=1; next }
      /^## /       { sect=0 }
      sect && /^\| *[0-9]{4}-/ {
        gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3)
        printf "  [due %s] %s\n", $2, $3
      }
    ' "$WORK/OBLIGATIONS.md" 2>/dev/null)
    [ -n "$TODOS" ] && printf "%s\n" "$TODOS" || printf "  (none)\n"

    # ── Recurring (from ## Recurring — items overdue by frequency) ────────
    printf "\n▸ RECURRING\n"
    RECUR=$(awk -F'|' '
      /^## Recurring/ { sect=1; next }
      /^## /          { sect=0 }
      sect && /^\| *[A-Za-z]/ && !/Frequency/ && !/^[[:space:]]*\|[-|]/ {
        gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $4)
        freq=$2; item=$3; last=$4
        days=7
        if (freq ~ /[Dd]aily/)    days=1
        if (freq ~ /[Ww]eekly/)   days=7
        if (freq ~ /[Bb]iweekly/) days=14
        if (freq ~ /[Mm]onthly/)  days=30
        printf "%d|%s|%s\n", days, last, item
      }
    ' "$WORK/OBLIGATIONS.md" 2>/dev/null | while IFS='|' read -r days last item; do
      [ -z "$last" ] && { printf "  [due — never done] %s\n" "$item"; continue; }
      last_epoch=$(date -d "$last" +%s 2>/dev/null) || continue
      days_ago=$(( ($(date +%s) - last_epoch) / 86400 ))
      [ "$days_ago" -ge "$days" ] && printf "  [due — %d days ago] %s\n" "$days_ago" "$item"
    done)
    [ -n "$RECUR" ] && printf "%s\n" "$RECUR" || printf "  (all up to date)\n"

    # Korean streak/study block removed 2026-06-25 — Korean is now just an
    # interest, not a tracked daily obligation. No more streaks or study-day counts.

    # ── Next up (DELEGATIONS.md Outbox — priority "next" or "pri 1") ──────
    printf "\n▸ NEXT UP\n"
    NEXT=$(awk -F'|' '
      /^## Outbox/  { sect=1; next }
      /^## /        { sect=0 }
      sect && NF >= 5 && !/Project/ && !/^[[:space:]]*\|[-|]/ {
        gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); gsub(/^ +| +$/, "", $5)
        if ($5 ~ /next/ || $5 ~ /pri 1/)
          printf "  [%s] %s\n", $2, $3
      }
    ' "$WORK/DELEGATIONS.md" 2>/dev/null)
    [ -n "$NEXT" ] && printf "%s\n" "$NEXT" || printf "  (nothing flagged)\n"
    printf "\n"
  '';

  # bearing-prompt: weekly notebook prompt, pushed to the phone via ntfy (Sundays).
  #
  # Robie's notebooks are kept as a deliberate legacy document (ledger2/interests/journaling.md).
  # This is a self-administered version of Mass Observation's "Directive" mechanism: people don't
  # spontaneously write about the contents of their pockets or the price of groceries — they have
  # to be asked. It does NOT touch the daily free-writing; it's an optional weekly addition.
  #
  # The prompt bank is ~/work/templates/notebook-prompts.md, read at RUNTIME (not baked into the
  # store) so Robie can edit prompts without a rebuild. Rotation state is ~/work/.prompt-state:
  # nothing repeats until the bank is exhausted, and the same category doesn't run twice in a row.
  # Prompts are identified by a hash of their text, so reordering the file is a no-op and editing
  # a prompt makes it eligible again.
  #
  # `bearing-prompt --dry-run` prints the pick without sending or recording it.
  bearingPrompt = pkgs.writeShellScriptBin "bearing-prompt" ''
    exec ${pkgs.python3}/bin/python3 - "$@" <<'PYEOF'
    import hashlib, json, os, random, subprocess, sys

    WORK   = "${workDir}"
    BANK   = os.path.join(WORK, "templates", "notebook-prompts.md")
    STATE  = os.path.join(WORK, ".prompt-state")
    TOPICF = os.path.join(WORK, ".ntfy-topic")
    SERVER = "${ntfyServer}"
    DRY    = "--dry-run" in sys.argv[1:]

    if not os.path.exists(BANK):
        print(f"bearing-prompt: no prompt bank at {BANK}", file=sys.stderr)
        sys.exit(1)

    # Parse the markdown table: | category | sketch | prompt |
    prompts = []
    for line in open(BANK, encoding="utf-8"):
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 3:
            continue
        cat, sketch, text = cells
        if cat.lower() == "category" or set(cat) <= set("-: "):
            continue          # header row / separator row
        prompts.append({
            "id":     hashlib.sha256(text.encode("utf-8")).hexdigest()[:12],
            "cat":    cat,
            "sketch": sketch.lower() in ("yes", "y", "true"),
            "text":   text,
        })

    if not prompts:
        print("bearing-prompt: prompt bank parsed to zero prompts", file=sys.stderr)
        sys.exit(1)

    try:
        state = json.load(open(STATE, encoding="utf-8"))
    except Exception:
        state = {}
    used     = set(state.get("used", []))
    last_cat = state.get("last_cat")

    pool = [p for p in prompts if p["id"] not in used]
    if not pool:                      # bank exhausted — start a fresh cycle
        used, pool = set(), list(prompts)
    spread = [p for p in pool if p["cat"] != last_cat]
    choice = random.choice(spread or pool)

    title = "Notebook prompt" + (" — draw + write" if choice["sketch"] else "")
    body  = choice["text"] + f"\n\n[{choice['cat']}]"

    if DRY:
        print(f"{title}\n{body}")
        sys.exit(0)

    topic = ""
    if os.path.exists(TOPICF):
        topic = open(TOPICF, encoding="utf-8").read().strip()
    if not topic:
        # Same failure mode as bearing-checkin: no topic file, no push. Say so on stderr
        # rather than silently succeeding — a silent no-op here means a missed week.
        print("bearing-prompt: no ntfy topic in .ntfy-topic, not sending", file=sys.stderr)
        sys.exit(1)

    r = subprocess.run([
        "${pkgs.curl}/bin/curl", "-sS", "--fail", "--max-time", "20",
        "-H", f"Title: {title}",
        "-H", "Priority: default",
        "-H", "Tags: pencil2" if choice["sketch"] else "Tags: memo",
        "-d", body,
        f"{SERVER}/{topic}",
    ], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"bearing-prompt: ntfy publish failed: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)

    # Only record the pick once it actually went out.
    used.add(choice["id"])
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"used": sorted(used), "last_cat": choice["cat"]}, f, indent=2)
    os.replace(tmp, STATE)
    print(f"sent [{choice['cat']}] {choice['text'][:60]}...")
    PYEOF
  '';

  # bearing-log: open (or create) today's log file in $EDITOR.
  # Creates ~/work/log/YYYY-MM-DD.md with the standard template if it doesn't exist.
  bearingLog = pkgs.writeShellScriptBin "bearing-log" ''
    TODAY=$(date +%Y-%m-%d)
    LOG_DIR="${workDir}/log"
    LOG_FILE="$LOG_DIR/$TODAY.md"

    mkdir -p "$LOG_DIR"

    if [ ! -f "$LOG_FILE" ]; then
      printf "# %s\n\n## Morning\n- State:\n- Plan:\n- Todos checked:\n\n## Activities\n-\n\n## Evening gap\n-\n\n## Notes\n-\n" \
        "$TODAY" > "$LOG_FILE"
    fi

    exec ''${EDITOR:-nano} "$LOG_FILE"
  '';
in
{
  # ── Scripts on PATH ──────────────────────────────────────────────────────
  environment.systemPackages = [
    bearingCmd bearingNotify bearingCheckin bearingBriefing bearingActivity
    bearingLint bearingIngest bearingStatus bearingLog bearingPrompt bearingDoctor
    pkgs.qmd
  ];

  # ── Maintenance timers ───────────────────────────────────────────────────
  # NOTE: The Bearing moved from a push model to a pull model (2026-06-25).
  # Only the autonomous maintenance jobs (lint, ingest, qmd index) are scheduled;
  # sessions start on demand (`bearing` command / Super+B).

  systemd.user.services.bearing-lint = {
    description = "The Bearing — daily Ledger lint";
    after       = [ "default.target" ];
    serviceConfig = {
      Type        = "oneshot";
      ExecStart   = "${bearingLint}/bin/bearing-lint";
      # SHELL is mandatory here. systemd user units inherit almost no environment,
      # and Robie's login shell is fish; without a POSIX shell Claude's Bash tool
      # fails with "No suitable shell found" and silently skips 5 of the 8
      # mechanical checks (stubs, undated, orphan scan, wikilink sweep, mtime
      # drift). Diagnosed 2026-08-16 after the checks had been dark for weeks.
      Environment = [ "SSH_AUTH_SOCK=" "SHELL=/bin/sh" ];
    };
  };
  systemd.user.timers.bearing-lint = {
    description = "The Bearing — daily Ledger lint timer";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon-Sun ${lintTime}";
      Persistent = true;
    };
  };

  # Runs 15 min before the lint so a broken Bearing is reported before the lint
  # (which depends on a working Claude session) has a chance to fail confusingly.
  systemd.user.services.bearing-doctor = {
    description = "The Bearing — health check of its own state";
    after       = [ "default.target" ];
    # git is NOT in the default user-unit PATH. Proven on the first timer run
    # (2026-08-09): without it the unpushed check reported both repos as "not a
    # readable git repo" while journal-coverage saw no commits and silently
    # PASSED. A blind check that reports success is worse than no check.
    path        = [ pkgs.git ];
    serviceConfig = {
      Type        = "oneshot";
      ExecStart   = "${bearingDoctor}/bin/bearing-doctor";
      Environment = [ "SSH_AUTH_SOCK=" ];
      # Findings are a normal outcome, not a unit failure — otherwise every
      # stale-interests warning leaves a failed unit lying around, which is
      # exactly what poisons `nh os switch` (see nixos-config.md → Gotchas).
      SuccessExitStatus = "0 1";
    };
  };
  systemd.user.timers.bearing-doctor = {
    description = "The Bearing — daily self-check timer";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon-Sun ${doctorTime}";
      Persistent = true;
    };
  };

  systemd.user.services.bearing-ingest = {
    description = "The Bearing — nightly Ledger ingestion from ~/raw/";
    after       = [ "default.target" ];
    serviceConfig = {
      Type        = "oneshot";
      ExecStart   = "${bearingIngest}/bin/bearing-ingest";
      Environment = [ "SSH_AUTH_SOCK=" ];
    };
  };
  systemd.user.timers.bearing-ingest = {
    description = "The Bearing — nightly Ledger ingestion timer";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon-Sun ${ingestTime}";
      Persistent = true;
    };
  };

  # Weekly notebook prompt (2026-08-02). Not a "session" — it's a one-way push that
  # feeds Robie's analog notebook, so it survives the pull-model rule against scheduled
  # prompts: it asks nothing of The Bearing and nothing of him.
  systemd.user.services.bearing-prompt = {
    description = "The Bearing — weekly notebook prompt";
    after       = [ "default.target" "network-online.target" ];
    serviceConfig = {
      Type        = "oneshot";
      ExecStart   = "${bearingPrompt}/bin/bearing-prompt";
      Environment = [ "SSH_AUTH_SOCK=" ];
    };
  };
  systemd.user.timers.bearing-prompt = {
    description = "The Bearing — weekly notebook prompt timer";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = promptTime;
      # Persistent: if the laptop is asleep or off Sunday morning, the prompt fires
      # on the next boot rather than skipping the week entirely.
      Persistent = true;
    };
  };

  systemd.user.services.qmd-update = {
    description = "QMD — re-index markdown collections and refresh embeddings";
    after       = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      # `qmd update` refreshes the BM25/keyword index but does NOT embed — it
      # only prints a reminder to run `qmd embed`. Embed second so semantic
      # (vsearch/query) results stay current too. Both are incremental: update
      # only touches changed files, embed only vectors hashes that lack them.
      # oneshot runs these sequentially and aborts if update fails.
      ExecStart = [
        "${pkgs.qmd}/bin/qmd update"
        "${pkgs.qmd}/bin/qmd embed"
      ];
    };
  };
  systemd.user.timers.qmd-update = {
    description = "QMD — hourly re-index timer (no catch-up on wake)";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      # Persistent omitted — missed runs while asleep are skipped, not replayed
    };
  };
}
