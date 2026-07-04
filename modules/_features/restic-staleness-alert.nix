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
  # NB: no `sed`/`awk` here — selection is pure coreutils (head|tail + bash param
  # expansion) so the script can't break on a missing-binary PATH (it did once:
  # `sed: command not found` made it fail blind, 2026-06-14). Logs PASS/FAIL to the
  # journal (so a failed filename is recoverable) and writes a success message that
  # the user notifier shows as an auto-expiring popup.
  restoreTest = pkgs.writeShellScript "restic-restore-test" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.restic ]}
    export RESTIC_REPOSITORY="${repo}"
    export RESTIC_PASSWORD_FILE="${pwPath}"
    export RESTIC_CACHE_DIR="/var/cache/restic-staleness"
    CAP=${toString cfg.restoreTestMaxFileBytes}
    LIST=$(mktemp); TARGET="${stateDir}/restore-test"; OK="${stateDir}/restore-ok"
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
      echo "restore-test: no candidates listed (repo unreachable/empty) — skipping, no alarm"
      rm -f "$LIST"; rmdir "$TARGET" 2>/dev/null || true
      exit 0
    fi

    idx=$(( RANDOM % n + 1 ))
    line=$(head -n "$idx" "$LIST" | tail -n 1)
    expected=''${line%%	*}; file=''${line#*	}
    rm -f "$LIST"

    if [ -z "$file" ] || [ -z "$expected" ]; then
      # Internal/selection error — NOT a backup failure. Don't raise the scary alert.
      echo "restore-test: INTERNAL ERROR selecting a candidate (line='$line')" >&2
      rm -rf "$TARGET"; exit 1
    fi

    if restic -o sftp.command=${sshCmd} restore latest --include "$file" --target "$TARGET" >/dev/null 2>&1 \
       && got=$(stat -c %s "$TARGET$file" 2>/dev/null) && [ "$got" = "$expected" ]; then
      echo "restore-test: PASS — restored $file ($got bytes, verified)"
      ${alertHelper} clear restore-test
      printf 'Restored %s (%s bytes verified) — %s\n' "$file" "$got" "$(date '+%a %H:%M')" > "$OK"
    else
      echo "restore-test: FAIL — $file (expected $expected bytes, got ''${got:-none})" >&2
      rm -f "$OK"
      ${alertHelper} raise restore-test "Restore test FAILED for ONE RANDOMLY-CHOSEN file: $file (expected $expected bytes, got ''${got:-none}). This tested a single random file — it may be a one-off (that file/blob) rather than total loss. Confirm before flipping out: re-run 'systemctl start restic-restore-test' or do a manual restore (see restic.md). Treat as a real, systemic problem only if it keeps failing on different files."
    fi
    rm -rf "$TARGET"
  '';

  # User: surface all active alerts in the live desktop session. Idempotent —
  # shows once per distinct alert state (a marker in the per-user runtime dir
  # prevents re-popping what's already displayed, so a short timer can't spam and
  # a manual dismiss is respected). Reads whatever is in alerts/ regardless of how
  # it got there, so it never depends on catching a dir-change transition.
  notify = pkgs.writeShellScript "restic-staleness-notify" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.libnotify ]}
    [ "$(id -un)" = "${cfg.user}" ] || exit 0
    rt="/run/user/$(id -u)"

    # Failures → persistent (critical, no timeout). Shown once per distinct state.
    marker="$rt/restic-staleness-shown"
    msgs=$(cat ${stateDir}/alerts/* 2>/dev/null || true)
    if [ -z "$msgs" ]; then
      rm -f "$marker"
    elif [ ! -f "$marker" ] || [ "$(cat "$marker")" != "$msgs" ]; then
      notify-send -a "Backup Monitor" -u critical -t 0 -r 71717 \
        -i dialog-warning "⚠ Backup check failed" "$msgs" || true
      printf '%s' "$msgs" > "$marker"
    fi

    # Restore-test success → auto-expiring (normal, ~8s). Distinct replace-id so it
    # never clobbers a failure popup. Shown once per distinct result.
    okmarker="$rt/restic-restore-ok-shown"
    ok=$(cat ${stateDir}/restore-ok 2>/dev/null || true)
    if [ -n "$ok" ] && { [ ! -f "$okmarker" ] || [ "$(cat "$okmarker")" != "$ok" ]; }; then
      notify-send -a "Backup Monitor" -u normal -t 8000 -r 71718 \
        -i dialog-information "✅ Restore test passed" "$ok" || true
      printf '%s' "$ok" > "$okmarker"
    fi
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
      # LAN path (was the tailnet URL until 2026-07-03): backup alerts are
      # load-bearing and must not depend on Tailscale (standing rule; TS is being
      # decommissioned). Plain HTTP by design — the LAN vhost has no cert; the
      # payload is an alert on a topic whose NAME is the secret. See ntfy.nix.
      type = lib.types.str; default = "http://ntfy.home.lab";
      description = "ntfy server base URL (LAN path, deliberately not the tailnet).";
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
      "f ${stateDir}/restore-ok 0644 root root -"      # seed: restore-test success msg
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
      # Short interval: the idempotent notifier won't re-pop unchanged alerts, so
      # this just bounds worst-case latency to ~5 min without spamming.
      timerConfig = { OnStartupSec = "30s"; OnUnitActiveSec = "5min"; Persistent = true; };
    };

    # Event-driven trigger: fire the notifier the instant a check writes/clears an
    # alert, so the desktop popup never races the (independently-timed) root check.
    # The hourly timer above remains a backstop. The alerts dir is 0755, so the
    # user manager can inotify-watch it.
    systemd.user.paths.restic-staleness-notify = {
      description = "Watch restic alerts dir + success file; surface changes immediately";
      wantedBy = [ "paths.target" ];
      # Watch the alerts dir (create/delete of failure alerts) AND the restore-ok
      # file directly (PathModified on a file catches in-place writes, unlike on a
      # dir). The 5-min timer is the backstop.
      pathConfig = { PathModified = [ "${stateDir}/alerts" "${stateDir}/restore-ok" ]; };
    };
  };
}
