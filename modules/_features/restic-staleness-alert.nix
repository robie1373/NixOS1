# modules/_features/restic-staleness-alert.nix
#
# Alert when restic NAS backups have not succeeded for too long.
#
# Why this exists: the backup's NAS-reachability ExecCondition skips the run
# (systemd Result=exec-condition = "skipped", NOT "failed") whenever the NAS is
# down or the laptop was suspended. systemd never alerts on a skip, so a
# multi-day gap is completely silent. This watches the last-success stamp written
# by the restic module (modules/_features/restic.nix) and raises a persistent
# desktop (dunst) + phone (ntfy) alert if it goes stale.
#
# Runs as a *user* systemd timer so dunstify reaches the live graphical session,
# and fires shortly after login — i.e. exactly when Robie is back at the machine.

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.resticStalenessAlert;

  checkScript = pkgs.writeShellScript "restic-staleness-check" ''
    set -u
    # Only the intended desktop user raises the alert (user units run per-session).
    [ "$(${pkgs.coreutils}/bin/id -un)" = "${cfg.user}" ] || exit 0

    now=$(${pkgs.coreutils}/bin/date +%s)
    if [ -e "${cfg.stampFile}" ]; then
      last=$(${pkgs.coreutils}/bin/stat -c %Y "${cfg.stampFile}")
    else
      last=0
    fi
    age=$(( (now - last) / 86400 ))
    [ "$age" -lt ${toString cfg.maxAgeDays} ] && exit 0

    if [ "$last" -gt 0 ]; then
      when=$(${pkgs.coreutils}/bin/date -d "@$last" '+%Y-%m-%d %H:%M')
    else
      when="never"
    fi
    body="No successful flipper backup in $age day(s) (last: $when). If the laptop was closed or the NAS was down, reconnect and it should catch up on the next run; otherwise check: systemctl status restic-backups-nas."

    # Desktop — persistent: critical urgency never auto-expires, -t 0 reinforces.
    ${pkgs.dunst}/bin/dunstify -a "Backup Monitor" -u critical -t 0 -i dialog-warning \
      "⚠ Backups are stale" "$body" || true

    # Phone — ntfy (topic read from a file at runtime, same convention as the
    # bearing notifier; silently skip if the file is absent).
    topic=$(${pkgs.coreutils}/bin/cat "${cfg.ntfyTopicFile}" 2>/dev/null || true)
    if [ -n "$topic" ]; then
      ${pkgs.curl}/bin/curl -fsS \
        -H "Title: ⚠ flipper backups stale ($age d)" \
        -H "Priority: high" \
        -H "Tags: floppy_disk,warning" \
        -d "$body" \
        "${cfg.ntfyServer}/$topic" >/dev/null || true
    fi
  '';
in
{
  options.mySystem.resticStalenessAlert = {
    enable = lib.mkEnableOption "persistent desktop + ntfy alert when restic backups go stale";

    user = lib.mkOption {
      type        = lib.types.str;
      default     = "robie";
      description = "Desktop user whose session raises the alert and owns the ntfy topic file.";
    };

    maxAgeDays = lib.mkOption {
      type        = lib.types.int;
      default     = 3;
      description = "Alert if the newest successful backup is at least this many days old.";
    };

    stampFile = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/restic-staleness/last-success";
      description = "Stamp file touched on each successful backup by modules/_features/restic.nix.";
    };

    ntfyServer = lib.mkOption {
      type        = lib.types.str;
      default     = "https://ntfy.vimba-stairs.ts.net";
      description = "ntfy server base URL.";
    };

    ntfyTopicFile = lib.mkOption {
      type        = lib.types.str;
      default     = "/home/robie/work/.ntfy-topic";
      description = "File containing the ntfy topic to publish to. Skipped if missing.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.restic-staleness = {
      description = "Alert if restic NAS backups are stale";
      serviceConfig = {
        Type      = "oneshot";
        ExecStart = "${checkScript}";
      };
    };

    systemd.user.timers.restic-staleness = {
      description = "Periodic restic backup staleness check";
      wantedBy    = [ "timers.target" ];
      timerConfig = {
        OnStartupSec = "3min";        # shortly after the session starts (login/resume)
        OnCalendar   = "*-*-* 11:00";  # and once a day while logged in
        Persistent   = true;
      };
    };
  };
}
