# modules/_system/omada-controller.nix
#
# TP-Link Omada SDN controller — manages EAP773 APs and SG3210XHP-M2 switch.
#
# Access: https://<ip>:8843 (web UI, self-signed cert on first boot)
#         https://<ip>:8043 (HTTP, redirects to HTTPS)
#
# No nginx proxy — Omada runs its own HTTPS stack.
# No agenix secrets — admin account created via web UI on first boot.
# Tailscale provided by server-common.
#
# AP adoption: tell APs to find controller at 192.168.20.50:8043
# or use Omada app discovery (UDP 27001 broadcast on VLAN 20).
#
# State lives in /var/lib/omada-controller/ — do not delete between rebuilds.

{ config, lib, ... }:

let
  cfg = config.mySystem.omada-controller;
in
{
  options.mySystem.omada-controller = {
    enable = lib.mkEnableOption "TP-Link Omada SDN controller";
  };

  config = lib.mkIf cfg.enable {

    # ── Omada controller ──────────────────────────────────────────────────────
    # Bundles MongoDB and Java internally — no separate DB service needed.
    # State dir: /var/lib/omada-controller/
    services.omada-controller = {
      enable = true;
      openFirewall = true;  # opens 8043, 8843, 29810-29816, 27001/UDP
    };

  };
}
