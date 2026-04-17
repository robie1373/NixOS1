# modules/_features/tailscale-watchdog.nix
#
# Systemd timer that checks Tailscale every 15 minutes and runs
# 'tailscale up' if BackendState is not "Running".
#
# Handles: transient network drops, daemon restarts, brief connectivity loss.
# Does NOT fix: expired node keys (BackendState = "NeedsLogin"). Tagged devices
# (tag:terraformhost) have non-expiring node keys, so NeedsLogin shouldn't
# occur in normal operation. If it does, re-auth manually and audit the
# tailnet admin console for auth key expiry.
#
# extraUpFlags: the watchdog passes whatever services.tailscale.extraUpFlags
# is set to, matching the flags used at initial join. This ensures tags and
# --ssh are not silently dropped on reconnect.
#
# Import in every host definition that has services.tailscale.enable = true.

{ config, lib, pkgs, ... }:

{
  systemd.services.tailscale-watchdog = {
    description = "Tailscale watchdog — reconnect if BackendState is not Running";
    after       = [ "tailscaled.service" "network-online.target" ];
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = pkgs.writeShellScript "tailscale-watchdog" ''
        STATE=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.BackendState // "unknown"' 2>/dev/null)
        if [ "$STATE" = "Running" ]; then
          exit 0
        fi
        echo "tailscale-watchdog: BackendState='$STATE' — running tailscale up"
        ${pkgs.tailscale}/bin/tailscale up ${lib.concatStringsSep " " config.services.tailscale.extraUpFlags}
      '';
    };
  };

  systemd.timers.tailscale-watchdog = {
    description = "Tailscale watchdog — reconnect check every 15 minutes";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "5min";   # first check 5 min after boot
      OnUnitActiveSec = "15min";  # then every 15 min
      Persistent      = false;    # missed firings not replayed — no point catching up
    };
  };
}
