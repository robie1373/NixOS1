{ lib, config, pkgs, ... }:

let
  cfg = config.myHome.bearing;

  # ── Scripts ────────────────────────────────────────────────────────────────

  # bearing-open: opens a terminal with a typed claude session.
  # Called by:
  #   - dunst script rule (args: appname summary body icon urgency → unknown $1, falls back to "bearing")
  #   - Hyprland Super+B bind (explicit "bearing" arg)
  # The case statement validates $1 so dunst's appname arg doesn't corrupt the type.
  bearingOpen = pkgs.writeShellScript "bearing-open" ''
    case "''${1}" in
      morning|checkin|afternoon|briefing|bearing) TYPE="''${1}" ;;
      *) TYPE="bearing" ;;
    esac
    exec ${cfg.terminal} -- bash -c "cd ${cfg.workDir} && claude $TYPE; exec bash"
  '';

  # bearing: ad-hoc user command. Runs a bearing session in the current terminal.
  # exec replaces the shell — terminal closes when the session ends.
  bearingCmd = pkgs.writeShellScriptBin "bearing" ''
    cd ${cfg.workDir} && exec claude bearing
  '';

  # bearing-notify: sends a non-blocking desktop notification via dunst.
  # No -A flag — click handling is dunst's responsibility via the rule below.
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
      afternoon)
        TITLE="Afternoon Bearing"
        BODY="Last check-in of the day. How did it go?"
        URGENCY="low"
        ;;
      korean)
        TITLE="Korean lesson"
        BODY="Past you decided to study every day. Today's lesson is waiting."
        URGENCY="normal"
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
    ${pkgs.dunst}/bin/dunstify \
      -a "The Bearing" \
      -u "$URGENCY" \
      -t 0 \
      "$TITLE" "$BODY"
  '';

  # bearing-checkin: called by systemd timers. Fires desktop (dunst) and phone (ntfy) notifications.
  # ntfy topic is read from ~/work/.ntfy-topic at runtime — populate with:
  #   op read 'op://devops/temp ntfy topic bearing/password' > ~/work/.ntfy-topic
  # Silently skips ntfy if the file is missing.
  bearingCheckin = pkgs.writeShellScriptBin "bearing-checkin" ''
    TYPE="''${1:-checkin}"
    ${bearingNotify}/bin/bearing-notify "$TYPE" &
    TOPIC="$(cat ${cfg.workDir}/.ntfy-topic 2>/dev/null)"
    if [ -n "$TOPIC" ]; then
      case "$TYPE" in
        morning)
          TITLE="Morning Bearing"; MSG="Time to take a bearing."; PRI="default"; TAGS="compass" ;;
        checkin)
          TITLE="Check-in"; MSG="Worth a quick recalibration."; PRI="low"; TAGS="clock" ;;
        afternoon)
          TITLE="Afternoon Bearing"; MSG="Last check-in of the day."; PRI="low"; TAGS="sunset" ;;
        korean)
          TITLE="Korean lesson"; MSG="Today's lesson is waiting."; PRI="default"; TAGS="books" ;;
        *)
          TITLE="The Bearing"; MSG="Check in."; PRI="default"; TAGS="bell" ;;
      esac
      ${pkgs.curl}/bin/curl -s \
        -H "Title: $TITLE" \
        -H "Priority: $PRI" \
        -H "Tags: $TAGS" \
        -d "$MSG" \
        "${cfg.ntfy.server}/$TOPIC"
    fi
    wait
  '';

  # bearing-briefing: runs claude non-interactively to pre-gather morning context.
  # Substitutes {{RECENT_TOPICS}} in the template with section headers from the last
  # 3 briefing files so the agent avoids picking the same topics two days running.
  # Claude writes output to ~/work/briefing/YYYY-MM-DD.md per template instructions.
  # Requires templates/briefing-gather.md to exist in workDir.
  bearingBriefing = pkgs.writeShellScriptBin "bearing-briefing" ''
    mkdir -p ${cfg.workDir}/briefing
    cd ${cfg.workDir}
    ${pkgs.python3}/bin/python3 -c "
import os, sys
briefing_dir = '${cfg.workDir}/briefing'
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
template = open('${cfg.workDir}/templates/briefing-gather.md').read()
sys.stdout.write(template.replace('{{RECENT_TOPICS}}', recent))
" | ${pkgs.claude-code}/bin/claude --print \
        --allowedTools "WebSearch,WebFetch,Write"
  '';

  # bearing-activity: runs claude non-interactively to summarise yesterday's git activity.
  # Reads prompt from ~/work/templates/activity-gather.md via stdin pipe.
  # Claude writes output to ~/work/briefing/YYYY-MM-DD-activity.md per template instructions.
  # Requires templates/activity-gather.md to exist in workDir.
  # No network tools needed — git log is local. SSH_AUTH_SOCK cleared in service.
  bearingActivity = pkgs.writeShellScriptBin "bearing-activity" ''
    mkdir -p ${cfg.workDir}/briefing
    cd ${cfg.workDir}
    cat ${cfg.workDir}/templates/activity-gather.md \
      | ${pkgs.claude-code}/bin/claude --print \
          --allowedTools "Bash,Write"
  '';

  # bearing-status: offline status card — no AI, no network.
  # Reads OBLIGATIONS.md, DELEGATIONS.md, and study-robie.log and prints
  # a compact summary to stdout.
  bearingStatus = pkgs.writeShellScriptBin "bearing-status" ''
    TODAY=$(date +%Y-%m-%d)
    TOMORROW=$(date -d "tomorrow" +%Y-%m-%d)
    WORK="${cfg.workDir}"
    LANG_LOG="$HOME/languages/study-robie.log"

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

    # ── Korean ────────────────────────────────────────────────────────────
    printf "\n▸ KOREAN\n"
    if [ -f "$LANG_LOG" ]; then
      KOREAN_DATES=$(grep $'\tkorean\t' "$LANG_LOG" \
        | awk -F'\t' '{split($1,a,"T"); print a[1]}' | sort -u)
      TOTAL_DAYS=$(printf "%s\n" "$KOREAN_DATES" | grep -c '.')
      LAST_DATE=$(printf "%s\n" "$KOREAN_DATES" | tail -1)

      # Streak: count consecutive days ending at most recent studied day
      # (today if done today, yesterday if not yet done today — preserves
      # the "at-risk" streak so it shows before you do the day's lesson)
      STREAK=0
      if [ -n "$LAST_DATE" ]; then
        TODAY_EPOCH=$(date +%s)
        LAST_EPOCH=$(date -d "$LAST_DATE" +%s)
        DAYS_SINCE=$(( (TODAY_EPOCH - LAST_EPOCH) / 86400 ))
        if [ "$DAYS_SINCE" -le 1 ]; then
          CHECK=$(date -d "$LAST_DATE" +%s)
          while true; do
            CHECK_DATE=$(date -d "@''${CHECK}" +%Y-%m-%d)
            if printf "%s\n" "$KOREAN_DATES" | grep -qx "$CHECK_DATE"; then
              STREAK=$((STREAK + 1))
              CHECK=$((CHECK - 86400))
            else
              break
            fi
          done
        fi
      fi
      printf "  Last: %s  |  Streak: %s days  |  Total: %s unique days\n" \
        "$LAST_DATE" "$STREAK" "$TOTAL_DAYS"
    else
      printf "  (no study log found)\n"
    fi

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
    LOG_DIR="${cfg.workDir}/log"
    LOG_FILE="$LOG_DIR/$TODAY.md"

    mkdir -p "$LOG_DIR"

    if [ ! -f "$LOG_FILE" ]; then
      printf "# %s\n\n## Morning\n- State:\n- Plan:\n- Todos checked:\n\n## Activities\n-\n\n## Evening gap\n-\n\n## Notes\n-\n" \
        "$TODAY" > "$LOG_FILE"
    fi

    exec ''${EDITOR:-nano} "$LOG_FILE"
  '';

in {
  options.myHome.bearing = {
    enable = lib.mkEnableOption "The Bearing life-tracking assistant";

    workDir = lib.mkOption {
      type    = lib.types.str;
      default = "${config.home.homeDirectory}/work";
      description = "Working directory for The Bearing (Claude session and data files)";
    };

    terminal = lib.mkOption {
      type    = lib.types.str;
      default = "foot";
      description = "Terminal emulator to launch when opening The Bearing";
    };

    ntfy = {
      server = lib.mkOption {
        type    = lib.types.str;
        default = "https://ntfy.sh";
        description = "ntfy server URL";
      };
    };

    schedule = {
      briefing = lib.mkOption {
        type    = lib.types.str;
        default = "06:30";
        description = "Time for morning briefing pre-gather (runs claude --print headlessly)";
      };
      morning = lib.mkOption {
        type    = lib.types.str;
        default = "08:00";
        description = "Time for morning check-in notification";
      };
      checkin = lib.mkOption {
        type    = lib.types.str;
        default = "13:00";
        description = "Time for midday check-in notification";
      };
      afternoon = lib.mkOption {
        type    = lib.types.str;
        default = "16:30";
        description = "Time for afternoon check-in notification";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Scripts on PATH ────────────────────────────────────────────────────
    home.packages = [ bearingCmd bearingNotify bearingCheckin bearingBriefing bearingActivity bearingStatus bearingLog ];

    # ── Systemd timer + service units ──────────────────────────────────────

    systemd.user.services.bearing-briefing = {
      Unit = {
        Description = "The Bearing — morning briefing pre-gather";
        After       = [ "network-online.target" ];
      };
      Service = {
        Type        = "oneshot";
        ExecStart   = "${bearingBriefing}/bin/bearing-briefing";
        Environment = [ "SSH_AUTH_SOCK=" ];  # prevent 1Password prompts in unattended context
      };
    };
    systemd.user.timers.bearing-briefing = {
      Unit.Description = "The Bearing — morning briefing pre-gather timer";
      Timer = {
        OnCalendar = "Mon-Sun ${cfg.schedule.briefing}";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.bearing-activity = {
      Unit = {
        Description = "The Bearing — git activity pre-gather";
        After       = [ "default.target" ];
      };
      Service = {
        Type        = "oneshot";
        ExecStart   = "${bearingActivity}/bin/bearing-activity";
        Environment = [ "SSH_AUTH_SOCK=" ];  # git log is local; no 1Password prompts
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

    systemd.user.services.bearing-morning = {
      Unit = {
        Description = "The Bearing — morning check-in";
        After       = [ "graphical-session.target" ];
      };
      Service = {
        Type      = "oneshot";
        ExecStart = "${bearingCheckin}/bin/bearing-checkin morning";
      };
    };
    systemd.user.timers.bearing-morning = {
      Unit.Description = "The Bearing — morning check-in timer";
      Timer = {
        OnCalendar = "Mon-Sun ${cfg.schedule.morning}";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.bearing-checkin = {
      Unit = {
        Description = "The Bearing — midday check-in";
        After       = [ "graphical-session.target" ];
      };
      Service = {
        Type      = "oneshot";
        ExecStart = "${bearingCheckin}/bin/bearing-checkin checkin";
      };
    };
    systemd.user.timers.bearing-checkin = {
      Unit.Description = "The Bearing — midday check-in timer";
      Timer = {
        OnCalendar = "Mon-Sun ${cfg.schedule.checkin}";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.bearing-afternoon = {
      Unit = {
        Description = "The Bearing — afternoon check-in";
        After       = [ "graphical-session.target" ];
      };
      Service = {
        Type      = "oneshot";
        ExecStart = "${bearingCheckin}/bin/bearing-checkin afternoon";
      };
    };
    systemd.user.timers.bearing-afternoon = {
      Unit.Description = "The Bearing — afternoon check-in timer";
      Timer = {
        OnCalendar = "Mon-Sun ${cfg.schedule.afternoon}";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    # ── Dunst fix ─────────────────────────────────────────────────────────
    # mouse_left_click: trigger the action on click rather than just dismissing
    # bearing rule: when a "The Bearing" notification is actioned, open a terminal
    services.dunst.settings = {
      global.mouse_left_click = "do_action, close_notification";
      bearing = {
        appname = "The Bearing";
        script  = "${bearingOpen}";
      };
    };
  };
}
