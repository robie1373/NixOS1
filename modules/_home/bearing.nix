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
    home.packages = [ bearingCmd bearingNotify bearingCheckin bearingBriefing bearingActivity ];

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
