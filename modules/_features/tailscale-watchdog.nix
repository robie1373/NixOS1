# modules/_features/tailscale-watchdog.nix
#
# Systemd timer that checks Tailscale every 15 minutes and reconnects
# if BackendState is not "Running".
#
# State handling:
#   Running    → no-op, exit 0
#   Stopped    → tailscale up with extraUpFlags (node already registered, no auth key needed)
#   NoState    → restart tailscaled-autoconnect.service (needs auth key for initial join)
#   NeedsLogin → restart tailscaled-autoconnect.service (auth key required to re-auth)
#   other      → restart tailscaled-autoconnect.service (safe fallback)
#
# extraUpFlags: the watchdog passes whatever services.tailscale.extraUpFlags
# is set to, matching the flags used at initial join. This ensures tags and
# --ssh are not silently dropped on reconnect.
#
# TimeoutStartSec: capped at 60s so the service can never hang indefinitely
# waiting for interactive auth (e.g. if autoconnect itself fails).
#
# Import in every host definition that has services.tailscale.enable = true.

{ config, lib, pkgs, ... }:

{
  systemd.services.tailscale-watchdog = {
    description = "Tailscale watchdog — reconnect if BackendState is not Running";
    after       = [ "tailscaled.service" "network-online.target" ];
    wants       = [ "network-online.target" ];
    serviceConfig = {
      Type             = "oneshot";
      TimeoutStartSec  = "60";
      ExecStart = pkgs.writeShellScript "tailscale-watchdog" ''
        STATE=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.BackendState // "unknown"' 2>/dev/null)
        if [ "$STATE" = "Running" ]; then
          exit 0
        fi
        echo "tailscale-watchdog: BackendState='$STATE'"
        if [ "$STATE" = "Stopped" ]; then
          echo "tailscale-watchdog: reconnecting with tailscale up"
          ${pkgs.tailscale}/bin/tailscale up ${lib.concatStringsSep " " config.services.tailscale.extraUpFlags}
        else
          echo "tailscale-watchdog: auth required — restarting tailscaled-autoconnect"
          systemctl restart tailscaled-autoconnect.service
        fi
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
