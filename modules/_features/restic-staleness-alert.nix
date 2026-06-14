# modules/_features/restic-staleness-alert.nix
#
# Real backup monitoring for the NAS restic repo — two root-side checks that
# query the ACTUAL repository (not a proxy), plus a user-side notifier.
#
#   1. restic-snapshot-check  (every 6h): is there a recent snapshot?
#        `restic snapshots --json --latest 1` → alert if newest >= maxAgeDays.
#   2. restic-restore-test    (weekly):    can we actually get bytes back?
#        Picks a SEMI-RANDOM file (size-capped) from the latest snapshot,
#        restores it, asserts the byte count matches. Proves the full
#        decrypt→fetch→write path, which `restic snapshots` does not.
#
# Both need the root-only agenix repo creds, so they run as ROOT systemd
# services (no interactive sudo — root reads the secrets directly, exactly like
# the backup job). They read mySystem.restic.{nasUser,nasHost,nasPath,paths} +
# the agenix secret paths declared by modules/_features/restic.nix, so host
# params never drift.
#
# Alerts: each check writes/clears its own file under ${stateDir}/alerts/ and
# sends a deduped (1/24h) ntfy. The user `restic-staleness-notify` timer raises a
# persistent dunst notification (-u critical -t 0) showing all active alerts.
# Persistent = it does NOT auto-expire and is NOT auto-cleared on recovery; Robie
# dismisses it himself (per request). While a problem persists the notification
# is replaced in place (fixed -r id) rather than re-stacked.

{ config, lib, pkgs, ... }:

let
  cfg      = config.mySystem.resticStalenessAlert;
  rcfg     = config.mySystem.restic;
  hostname = config.networking.hostName;

  pwPath  = config.age.secrets."restic-repo-password-${hostname}".path;
  keyPath = config.age.secrets."restic-backup-${hostname}".path;
  repo    = "sftp:${rcfg.nasUser}@${rcfg.nasHost}:/mnt/${rcfg.nasPath}";

  sshCmd = pkgs.writeShellScript "restic-monitor-ssh" ''
    exec ${pkgs.openssh}/bin/ssh \
      -s -i ${keyPath} \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      ${rcfg.nasUser}@${rcfg.nasHost} sftp
  '';

  stateDir = "/var/lib/restic-staleness";

  # Shared alert sink: `alert raise <name> <msg>` / `alert clear <name>`.
  alertHelper = pkgs.writeShellScript "restic-monitor-alert" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl ]}
    action="$1"; name="$2"; msg="''${3:-}"
    alerts="${stateDir}/alerts"; mkdir -p "$alerts"
    case "$action" in
      raise)
        printf '%s\n' "$msg" > "$alerts/$name"
        stamp="${stateDir}/notified.$name"
        if [ ! -e "$stamp" ] || [ $(( $(date +%s) - $(stat -c %Y "$stamp") )) -ge 86400 ]; then
          topic=$(cat "${cfg.ntfyTopicFile}" 2>/dev/null || true)
          if [ -n "$topic" ] && curl -fsS \
               -H "Title: ⚠ flipper backup: $name" -H "Priority: high" \
               -H "Tags: floppy_disk,warning" -d "$msg" \
               "${cfg.ntfyServer}/$topic" >/dev/null 2>&1; then
            touch "$stamp"
          fi
        fi ;;
      clear)
        rm -f "$alerts/$name" "${stateDir}/notified.$name" ;;
    esac
  '';

  # 1. Is there a recent snapshot? (queries the real repo)
  snapshotCheck = pkgs.writeShellScript "restic-snapshot-check" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.restic ]}
    export RESTIC_REPOSITORY="${repo}"
    export RESTIC_PASSWORD_FILE="${pwPath}"
    export RESTIC_CACHE_DIR="/var/cache/restic-staleness"
    LASTVERIFY="${stateDir}/last-verify"; MAXAGE=${toString cfg.maxAgeDays}
    now=$(date +%s)

    if out=$(restic -o sftp.command=${sshCmd} snapshots --json --latest 1 2>/dev/null); then
      touch "$LASTVERIFY"
      ts=$(printf '%s' "$out" | grep -oE '"time":"[^"]+"' | tail -1 | sed 's/.*"time":"//; s/".*//')
      if [ -z "$ts" ]; then
        ${alertHelper} raise snapshot-age "Backup repo is reachable but contains NO snapshots."
      else
        epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
        age=$(( (now - epoch) / 86400 ))
        when=$(date -d "$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$ts")
        if [ "$age" -ge "$MAXAGE" ]; then
          ${alertHelper} raise snapshot-age "Newest backup snapshot is $age days old (latest: $when). Repo is reachable — backups have lapsed."
        else
          ${alertHelper} clear snapshot-age
        fi
      fi
    else
      # Repo unreachable: only alarm if we have not verified for >= MAXAGE days.
      if [ ! -e "$LASTVERIFY" ] || [ $(( now - $(stat -c %Y "$LASTVERIFY") )) -ge $(( MAXAGE * 86400 )) ]; then
        ${alertHelper} raise snapshot-age "Cannot verify backups: repo unreachable, and no successful check in >= $MAXAGE days."
      fi
    fi
  '';

  # 2. Can we actually restore? Pick a semi-random small file and verify bytes.
  restoreTest = pkgs.writeShellScript "restic-restore-test" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.restic ]}
    export RESTIC_REPOSITORY="${repo}"
    export RESTIC_PASSWORD_FILE="${pwPath}"
    export RESTIC_CACHE_DIR="/var/cache/restic-staleness"
    CAP=${toString cfg.restoreTestMaxFileBytes}
    LIST=$(mktemp); TARGET="${stateDir}/restore-test"
    rm -rf "$TARGET"; mkdir -p "$TARGET"

    # Bounded candidate list: regular files, 0 < size <= CAP, from the backup
    # paths. head closes the pipe early so `restic ls` stops (bounded time).
    # NOTE: selection is biased toward the traversal-early part of the tree;
    # good enough to rotate files, not a uniform sample. See restic.md.
    restic -o sftp.command=${sshCmd} ls -l latest ${lib.escapeShellArgs rcfg.paths} 2>/dev/null \
      | while read -r mode uid gid size rest; do
          case "$mode" in -*) ;; *) continue ;; esac
          case "$size" in ""|*[!0-9]*) continue ;; esac
          [ "$size" -gt 0 ] && [ "$size" -le "$CAP" ] || continue
          p="''${rest#* }"; p="''${p#* }"
          printf '%s\t%s\n' "$size" "$p"
        done | head -n ${toString cfg.restoreTestCandidateLimit} > "$LIST"

    n=$(wc -l < "$LIST")
    if [ "$n" -eq 0 ]; then
      # Couldn't list (repo unreachable / empty): don't false-alarm — the
      # snapshot-age check owns the "repo down too long" alert.
      rm -f "$LIST"; rmdir "$TARGET" 2>/dev/null || true
      exit 0
    fi

    idx=$(( RANDOM % n + 1 ))
    line=$(sed -n "''${idx}p" "$LIST")
    expected=''${line%%	*}; file=''${line#*	}
    rm -f "$LIST"

    if restic -o sftp.command=${sshCmd} restore latest --include "$file" --target "$TARGET" >/dev/null 2>&1 \
       && got=$(stat -c %s "$TARGET$file" 2>/dev/null) && [ "$got" = "$expected" ]; then
      ${alertHelper} clear restore-test
    else
      ${alertHelper} raise restore-test "Restore test FAILED for ONE RANDOMLY-CHOSEN file: $file (expected $expected bytes, got ''${got:-none}). This tested a single random file — it may be a one-off (that file/blob) rather than total loss. Confirm before flipping out: re-run 'systemctl start restic-restore-test' or do a manual restore (see restic.md). Treat as a real, systemic problem only if it keeps failing on different files."
    fi
    rm -rf "$TARGET"
  '';

  # User: surface all active alerts in the live desktop session.
  notify = pkgs.writeShellScript "restic-staleness-notify" ''
    set -u
    [ "$(${pkgs.coreutils}/bin/id -un)" = "${cfg.user}" ] || exit 0
    msgs=$(${pkgs.coreutils}/bin/cat ${stateDir}/alerts/* 2>/dev/null || true)
    [ -z "$msgs" ] && exit 0
    ${pkgs.dunst}/bin/dunstify -a "Backup Monitor" -u critical -t 0 -r 71717 \
      -i dialog-warning "⚠ Backup check failed" "$msgs" || true
  '';
in
{
  options.mySystem.resticStalenessAlert = {
    enable = lib.mkEnableOption "real restic backup monitoring (snapshot-age + restore test) with persistent desktop + ntfy alerts";

    user = lib.mkOption {
      type = lib.types.str; default = "robie";
      description = "Desktop user whose session raises the alert and owns the ntfy topic file.";
    };
    maxAgeDays = lib.mkOption {
      type = lib.types.int; default = 3;
      description = "Alert if the newest snapshot is at least this many days old (or unverifiable this long).";
    };
    restoreTestOnCalendar = lib.mkOption {
      type = lib.types.str; default = "Sun 11:00";
      description = "systemd OnCalendar for the weekly restore test.";
    };
    restoreTestMaxFileBytes = lib.mkOption {
      type = lib.types.int; default = 52428800;  # 50 MiB
      description = "Only pick restore-test candidate files at or under this size.";
    };
    restoreTestCandidateLimit = lib.mkOption {
      type = lib.types.int; default = 5000;
      description = "Cap the candidate file list (bounds `restic ls` time).";
    };
    ntfyServer = lib.mkOption {
      type = lib.types.str; default = "https://ntfy.vimba-stairs.ts.net";
      description = "ntfy server base URL.";
    };
    ntfyTopicFile = lib.mkOption {
      type = lib.types.str; default = "/home/robie/work/.ntfy-topic";
      description = "File containing the ntfy topic. Skipped if missing.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
      "d ${stateDir}/alerts 0755 root root -"
      "f ${stateDir}/last-verify 0644 root root -"     # seed: grace before first check
      "d /var/cache/restic-staleness 0700 root root -"
    ];

    systemd.services.restic-snapshot-check = {
      description = "Check the real restic repo for a recent snapshot";
      serviceConfig = { Type = "oneshot"; ExecStart = "${snapshotCheck}"; };
    };
    systemd.timers.restic-snapshot-check = {
      description = "Periodic real restic snapshot-age check";
      wantedBy = [ "timers.target" ];
      timerConfig = { OnBootSec = "10min"; OnUnitActiveSec = "6h"; Persistent = true; };
    };

    systemd.services.restic-restore-test = {
      description = "Weekly restic restore test (random file, verify bytes)";
      serviceConfig = { Type = "oneshot"; ExecStart = "${restoreTest}"; };
    };
    systemd.timers.restic-restore-test = {
      description = "Weekly restic restore test";
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = cfg.restoreTestOnCalendar; Persistent = true; RandomizedDelaySec = "30min"; };
    };

    systemd.user.services.restic-staleness-notify = {
      description = "Surface restic backup alerts on the desktop";
      serviceConfig = { Type = "oneshot"; ExecStart = "${notify}"; };
    };
    systemd.user.timers.restic-staleness-notify = {
      description = "Periodic desktop check of restic backup alerts";
      wantedBy = [ "timers.target" ];
      timerConfig = { OnStartupSec = "3min"; OnUnitActiveSec = "1h"; Persistent = true; };
    };

    # Event-driven trigger: fire the notifier the instant a check writes/clears an
    # alert, so the desktop popup never races the (independently-timed) root check.
    # The hourly timer above remains a backstop. The alerts dir is 0755, so the
    # user manager can inotify-watch it.
    systemd.user.paths.restic-staleness-notify = {
      description = "Watch restic alerts dir; surface changes immediately";
      wantedBy = [ "paths.target" ];
      pathConfig = { PathModified = "${stateDir}/alerts"; };
    };
  };
}
