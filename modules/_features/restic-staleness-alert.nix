# modules/_features/restic-staleness-alert.nix
#
# Alert when restic NAS backups are stale — by querying the ACTUAL repository,
# not a local proxy.
#
# Design note (why a direct query, root-side): an earlier version touched a
# success-stamp from the backup job's ExecStartPost and watched the stamp's age.
# That only monitors the *producer's self-report* — "the backup job said it
# succeeded" — and is blind to the repository itself (NAS-side data loss, repo
# corruption, retention pruning everything, a snapshot that exited 0 but didn't
# persist). This version runs `restic snapshots --json --latest 1` against the
# real repo and checks the newest snapshot's age — the same thing `sudo restic-nas
# snapshots` shows by hand. That needs the repo password + SSH key, which are
# root-only agenix secrets, so the check is a ROOT systemd service (no interactive
# sudo — root reads the secrets directly, exactly like the backup job does).
#
# Split responsibilities:
#   - root  `restic-snapshot-check`  : queries the repo, decides stale/healthy,
#                                       writes a state/alert file, sends ntfy.
#   - user  `restic-staleness-notify`: reads the alert file, raises a persistent
#                                       dunst notification in the live session.
#
# Reads mySystem.restic.{nasUser,nasHost,nasPath} and the agenix secret paths
# that modules/_features/restic.nix already declares, so host params never drift.

{ config, lib, pkgs, ... }:

let
  cfg      = config.mySystem.resticStalenessAlert;
  rcfg     = config.mySystem.restic;
  hostname = config.networking.hostName;

  pwPath  = config.age.secrets."restic-repo-password-${hostname}".path;
  keyPath = config.age.secrets."restic-backup-${hostname}".path;
  repo    = "sftp:${rcfg.nasUser}@${rcfg.nasHost}:/mnt/${rcfg.nasPath}";

  # Same SFTP-subsystem invocation the backup uses (single token, no spaces).
  sshCmd = pkgs.writeShellScript "restic-staleness-ssh" ''
    exec ${pkgs.openssh}/bin/ssh \
      -s -i ${keyPath} \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      ${rcfg.nasUser}@${rcfg.nasHost} sftp
  '';

  stateDir = "/var/lib/restic-staleness";

  # ── root: query the real repo and decide ──────────────────────────────────
  checkScript = pkgs.writeShellScript "restic-snapshot-check" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.curl pkgs.restic ]}
    export RESTIC_REPOSITORY="${repo}"
    export RESTIC_PASSWORD_FILE="${pwPath}"
    export RESTIC_CACHE_DIR="/var/cache/restic-staleness"

    ALERT="${stateDir}/alert"          # present => desktop shows it; contents = message
    STATUS="${stateDir}/status"        # last result line, for `cat`/debugging
    NOTIFIED="${stateDir}/notified"    # ntfy dedup stamp (once per 24h)
    LASTVERIFY="${stateDir}/last-verify"  # last successful repo query
    MAXAGE=${toString cfg.maxAgeDays}
    now=$(date +%s)

    send_ntfy() {
      # de-duplicate: at most one push per 24h while stale
      if [ -e "$NOTIFIED" ] && [ $(( now - $(stat -c %Y "$NOTIFIED") )) -lt 86400 ]; then
        return 0
      fi
      topic=$(cat "${cfg.ntfyTopicFile}" 2>/dev/null || true)
      [ -z "$topic" ] && return 0
      if curl -fsS -H "Title: ⚠ flipper backups unverified" -H "Priority: high" \
           -H "Tags: floppy_disk,warning" -d "$1" \
           "${cfg.ntfyServer}/$topic" >/dev/null 2>&1; then
        touch "$NOTIFIED"
      fi
    }
    raise() { printf '%s\n' "$1" > "$ALERT"; printf '%s  ALERT: %s\n' "$(date -Is)" "$1" > "$STATUS"; send_ntfy "$1"; }
    clear() { rm -f "$ALERT" "$NOTIFIED"; printf '%s  ok: %s\n' "$(date -Is)" "$1" > "$STATUS"; }

    if out=$(restic -o sftp.command=${sshCmd} snapshots --json --latest 1 2>/dev/null); then
      touch "$LASTVERIFY"
      ts=$(printf '%s' "$out" | grep -oE '"time":"[^"]+"' | tail -1 | sed 's/.*"time":"//; s/".*//')
      if [ -z "$ts" ]; then
        raise "Backup repo is reachable but contains NO snapshots."
      else
        epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
        age=$(( (now - epoch) / 86400 ))
        when=$(date -d "$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$ts")
        if [ "$age" -ge "$MAXAGE" ]; then
          raise "Newest backup snapshot is $age days old (latest: $when). Repo is reachable — backups have lapsed."
        else
          clear "newest snapshot $when ($age d old)"
        fi
      fi
    else
      # Repo query failed (NAS down / network). Not necessarily stale backups —
      # only alarm if we have not been able to VERIFY for >= MAXAGE days.
      if [ ! -e "$LASTVERIFY" ] || [ $(( now - $(stat -c %Y "$LASTVERIFY") )) -ge $(( MAXAGE * 86400 )) ]; then
        raise "Cannot verify backups: repo unreachable, and no successful check in >= $MAXAGE days."
      else
        printf '%s  repo unreachable (transient — within grace)\n' "$(date -Is)" > "$STATUS"
      fi
    fi
  '';

  # ── user: surface the alert file in the live desktop session ───────────────
  notifyScript = pkgs.writeShellScript "restic-staleness-notify" ''
    set -u
    [ "$(${pkgs.coreutils}/bin/id -un)" = "${cfg.user}" ] || exit 0
    ALERT="${stateDir}/alert"
    if [ -s "$ALERT" ]; then
      # -r: fixed id so repeats replace rather than stack. critical+(-t 0): persists.
      ${pkgs.dunst}/bin/dunstify -a "Backup Monitor" -u critical -t 0 -r 71717 \
        -i dialog-warning "⚠ Backups not verified" "$(${pkgs.coreutils}/bin/cat "$ALERT")" || true
    fi
  '';
in
{
  options.mySystem.resticStalenessAlert = {
    enable = lib.mkEnableOption "alert (persistent desktop + ntfy) when the real restic repo has no recent snapshot";

    user = lib.mkOption {
      type = lib.types.str; default = "robie";
      description = "Desktop user whose session raises the alert and owns the ntfy topic file.";
    };
    maxAgeDays = lib.mkOption {
      type = lib.types.int; default = 3;
      description = "Alert if the newest snapshot in the repo is at least this many days old (or unverifiable this long).";
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
      "f ${stateDir}/last-verify 0644 root root -"   # seed: grace before first check
      "d /var/cache/restic-staleness 0700 root root -"
    ];

    # Root: the authoritative repo query.
    systemd.services.restic-snapshot-check = {
      description = "Check the real restic repo for a recent snapshot";
      serviceConfig = { Type = "oneshot"; ExecStart = "${checkScript}"; };
    };
    systemd.timers.restic-snapshot-check = {
      description = "Periodic real restic snapshot-age check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec        = "10min";
        OnUnitActiveSec  = "6h";
        Persistent       = true;
      };
    };

    # User: show the result in the live session, when logged in.
    systemd.user.services.restic-staleness-notify = {
      description = "Surface restic staleness alert on the desktop";
      serviceConfig = { Type = "oneshot"; ExecStart = "${notifyScript}"; };
    };
    systemd.user.timers.restic-staleness-notify = {
      description = "Periodic desktop check of restic staleness state";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnStartupSec    = "3min";
        OnUnitActiveSec = "1h";
        Persistent      = true;
      };
    };
  };
}
