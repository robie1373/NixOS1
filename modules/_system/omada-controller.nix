# modules/_system/omada-controller.nix
#
# TP-Link Omada SDN controller — manages EAP773 APs and SG3210XHP-M2 switch.
#
# Omada controller is not in nixpkgs; runs via Docker (mbentley/omada-controller).
# State persists in /var/lib/omada-controller/ across container restarts and rebuilds.
#
# Access: https://<ip>:8843 (web UI, self-signed cert on first boot)
#         https://<ip>:8043 (HTTP, redirects to HTTPS)
#
# AP adoption inform URL: http://192.168.20.50:8043
# No agenix secrets — admin account is created via web UI on first boot.

{ config, lib, ... }:

let
  cfg = config.mySystem.omada-controller;
in
{
  options.mySystem.omada-controller = {
    enable = lib.mkEnableOption "TP-Link Omada SDN controller (Docker)";
  };

  config = lib.mkIf cfg.enable {

    # ── Docker runtime ────────────────────────────────────────────────────────
    virtualisation.docker.enable = true;

    # ── Omada controller container ────────────────────────────────────────────
    # mbentley/omada-controller is the standard community image for self-hosted
    # Omada deployments. State dir: /var/lib/omada-controller/
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers.omada-controller = {
      image = "mbentley/omada-controller:latest";
      volumes = [
        "/var/lib/omada-controller/data:/opt/tplink/EAPController/data"
        "/var/lib/omada-controller/logs:/opt/tplink/EAPController/logs"
        "/var/lib/omada-controller/work:/opt/tplink/EAPController/work"
      ];
      ports = [
        "8043:8043"
        "8843:8843"
        "29810:29810/udp"
        "29811:29811"
        "29812:29812"
        "29813:29813"
        "27001:27001/udp"
      ];
      extraOptions = [ "--network=host" ];  # host networking for AP discovery broadcasts
    };

    # ── Firewall ──────────────────────────────────────────────────────────────
    networking.firewall.allowedTCPPorts = [ 8043 8843 29811 29812 29813 ];
    networking.firewall.allowedUDPPorts = [ 29810 27001 ];

  };
}
