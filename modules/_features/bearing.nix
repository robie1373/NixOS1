{ lib, config, pkgs, ... }:

# The Bearing — life-tracking assistant and daily rhythm system.
# Migrated from _home/bearing.nix (HM) to a NixOS system module (2026-05-20).
# Key changes from HM version:
#   - home.packages → environment.systemPackages
#   - services.dunst.* removed — noctalia is the notification daemon now
#   - dunstify → notify-send (libnotify); dunst-specific flags dropped
#   - bearingOpen script removed — dunst click rule no longer applies
#   - ${config.home.homeDirectory} → hardcoded /home/robie

let
  cfg = config.bearing;

  bearingCmd = pkgs.writeShellScriptBin "bearing" ''
    cd ${cfg.workDir} && exec claude bearing
  '';

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
    ${pkgs.libnotify}/bin/notify-send \
      --app-name "The Bearing" \
      -u "$URGENCY" \
      "$TITLE" "$BODY"
  '';

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
recent = '\n'.join('- ' + t for t in topics) or '(none yet -- all topics are fair game)'
template = open('${cfg.workDir}/templates/briefing-gather.md').read()
sys.stdout.write(template.replace('{{RECENT_TOPICS}}', recent))
" | ${pkgs.claude-code}/bin/claude --print \
        --allowedTools "WebSearch,WebFetch,Write"
  '';

  bearingActivity = pkgs.writeShellScriptBin "bearing-activity" ''
    mkdir -p ${cfg.workDir}/briefing
    cd ${cfg.workDir}
    cat ${cfg.workDir}/templates/activity-gather.md \
      | ${pkgs.claude-code}/bin/claude --print \
          --allowedTools "Bash,Write"
  '';

  bearingLint = pkgs.writeShellScriptBin "bearing-lint" ''
    mkdir -p ${cfg.workDir}/lint
    TODAY=$(date +%Y-%m-%d)
    LINT_FILE="${cfg.workDir}/lint/$TODAY.md"

    PROMPT=$(sed "s|{{LINT_FILE}}|$LINT_FILE|g" ${cfg.workDir}/templates/ledger-lint.md)
    SUMMARY=$(echo "$PROMPT" \
      | timeout 600 ${pkgs.claude-code}/bin/claude --print \
          --allowedTools "Bash,Read,Glob,Grep,Write" 2>/dev/null)
    EXIT=$?

    TOPIC="$(cat ${cfg.workDir}/.ntfy-topic 2>/dev/null)"
    if [ -n "$TOPIC" ]; then
      if [ "$EXIT" -eq 124 ]; then
        MSG="Lint timed out after 10 minutes."; PRI="low"; TAGS="warning"
      else
        MSG=$(printf "%s" "$SUMMARY" | grep -v '^[[:space:]]*$' | tail -1)
        [ -z "$MSG" ] && MSG="Lint complete -- see ~/work/lint/$TODAY.md"
        PRI="low"; TAGS="books"
      fi
      ${pkgs.curl}/bin/curl -s \
        -H "Title: Ledger lint" \
        -H "Priority: $PRI" \
        -H "Tags: $TAGS" \
        -d "$MSG" \
        "${cfg.ntfy.server}/$TOPIC"
    fi
  '';

  bearingStatus = pkgs.writeShellScriptBin "bearing-status" ''
    TODAY=$(date +%Y-%m-%d)
    TOMORROW=$(date -d "tomorrow" +%Y-%m-%d)
    WORK="${cfg.workDir}"
    LANG_LOG="$HOME/languages/study-robie.log"

    printf "══════════════════════════════════════\n"
    printf "  %s\n" "$(date '+%A, %B %-d %Y')"
    printf "══════════════════════════════════════\n"

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
      [ -z "$last" ] && { printf "  [due -- never done] %s\n" "$item"; continue; }
      last_epoch=$(date -d "$last" +%s 2>/dev/null) || continue
      days_ago=$(( ($(date +%s) - last_epoch) / 86400 ))
      [ "$days_ago" -ge "$days" ] && printf "  [due -- %d days ago] %s\n" "$days_ago" "$item"
    done)
    [ -n "$RECUR" ] && printf "%s\n" "$RECUR" || printf "  (all up to date)\n"

    printf "\n▸ KOREAN\n"
    if [ -f "$LANG_LOG" ]; then
      KOREAN_DATES=$(grep $'\tkorean\t' "$LANG_LOG" \
        | awk -F'\t' '{split($1,a,"T"); print a[1]}' | sort -u)
      TOTAL_DAYS=$(printf "%s\n" "$KOREAN_DATES" | grep -c '.')
      LAST_DATE=$(printf "%s\n" "$KOREAN_DATES" | tail -1)

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
  options.bearing = {
    enable = lib.mkEnableOption "The Bearing life-tracking assistant";

    workDir = lib.mkOption {
      type    = lib.types.str;
      default = "/home/robie/work";
    };

    terminal = lib.mkOption {
      type    = lib.types.str;
      default = "foot";
    };

    ntfy.server = lib.mkOption {
      type    = lib.types.str;
      default = "https://ntfy.sh";
    };

    schedule = {
      briefing = lib.mkOption { type = lib.types.str; default = "06:30"; };
      morning  = lib.mkOption { type = lib.types.str; default = "08:00"; };
      checkin  = lib.mkOption { type = lib.types.str; default = "13:00"; };
      lint     = lib.mkOption { type = lib.types.str; default = "16:00"; };
    };
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [
      bearingCmd bearingNotify bearingCheckin
      bearingBriefing bearingActivity bearingLint
      bearingStatus bearingLog
    ];

    systemd.user.services.bearing-briefing = {
      description = "The Bearing — morning briefing pre-gather";
      after       = [ "network-online.target" ];
      serviceConfig = {
        Type        = "oneshot";
        ExecStart   = "${bearingBriefing}/bin/bearing-briefing";
        Environment = "SSH_AUTH_SOCK=";
      };
    };
    systemd.user.timers.bearing-briefing = {
      description = "The Bearing — morning briefing pre-gather timer";
      timerConfig = {
        OnCalendar = "Mon-Sun ${cfg.schedule.briefing}";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.user.services.bearing-activity = {
      description = "The Bearing — git activity pre-gather";
      after       = [ "default.target" ];
      serviceConfig = {
        Type        = "oneshot";
        ExecStart   = "${bearingActivity}/bin/bearing-activity";
        Environment = "SSH_AUTH_SOCK=";
      };
    };
    systemd.user.timers.bearing-activity = {
      description = "The Bearing — git activity pre-gather timer";
      timerConfig = {
        OnCalendar = "Mon-Sun ${cfg.schedule.briefing}";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.user.services.bearing-morning = {
      description = "The Bearing — morning check-in";
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        Type      = "oneshot";
        ExecStart = "${bearingCheckin}/bin/bearing-checkin morning";
      };
    };
    systemd.user.timers.bearing-morning = {
      description = "The Bearing — morning check-in timer";
      timerConfig = {
        OnCalendar = "Mon-Sun ${cfg.schedule.morning}";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.user.services.bearing-checkin = {
      description = "The Bearing — midday check-in";
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        Type      = "oneshot";
        ExecStart = "${bearingCheckin}/bin/bearing-checkin checkin";
      };
    };
    systemd.user.timers.bearing-checkin = {
      description = "The Bearing — midday check-in timer";
      timerConfig = {
        OnCalendar = "Mon-Sun ${cfg.schedule.checkin}";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.user.services.bearing-lint = {
      description = "The Bearing — daily Ledger lint";
      after       = [ "default.target" ];
      serviceConfig = {
        Type        = "oneshot";
        ExecStart   = "${bearingLint}/bin/bearing-lint";
        Environment = "SSH_AUTH_SOCK=";
      };
    };
    systemd.user.timers.bearing-lint = {
      description = "The Bearing — daily Ledger lint timer";
      timerConfig = {
        OnCalendar = "Mon-Sun ${cfg.schedule.lint}";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
