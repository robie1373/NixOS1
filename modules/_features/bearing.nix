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
  ntfyServer = "https://ntfy.vimba-stairs.ts.net";
  lintTime   = "16:00";  # daily Ledger lint (headless, ntfy summary)
  ingestTime = "02:00";  # nightly ~/raw/ ingestion

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

    TOPIC="$(cat ${workDir}/.ntfy-topic 2>/dev/null)"
    if [ -n "$TOPIC" ]; then
      if [ "$EXIT" -eq 124 ]; then
        MSG="Lint timed out after 10 minutes."; PRI="low"; TAGS="warning"
      else
        MSG=$(printf "%s" "$SUMMARY" | grep -v '^[[:space:]]*$' | tail -1)
        [ -z "$MSG" ] && MSG="Lint complete — see ~/work/lint/$TODAY.md"
        PRI="low"; TAGS="books"
      fi
      ${pkgs.curl}/bin/curl -s \
        -H "Title: Ledger lint" \
        -H "Priority: $PRI" \
        -H "Tags: $TAGS" \
        -d "$MSG" \
        "${ntfyServer}/$TOPIC"
    fi
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
    bearingLint bearingIngest bearingStatus bearingLog
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
      Environment = [ "SSH_AUTH_SOCK=" ];
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
