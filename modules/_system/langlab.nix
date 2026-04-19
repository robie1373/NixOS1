# modules/_system/langlab.nix
#
# LangLab language learning suite.
# Python stdlib server + SQLite + Gemini AI (lessons, tutor).
# Two users: Robie (Korean) and Anna (Spanish).
#
# TLS: Tailscale HTTPS certs → /var/lib/nginx-certs/ (same pattern as ntfy).
# Secrets: langlab-env.age — EnvironmentFile with GEMINI_API_KEY + CLAUDE_API_KEY.
# State: /var/lib/langlab/ — study.db + languages/ audio files.
# Source: pinned via flake input `langlab` (github:robie1373/langlab).

{ config, lib, pkgs, inputs, ... }:

let
  cfg     = config.mySystem.langlab;
  certDir = "/var/lib/nginx-certs";
  src     = inputs.langlab;
in
{
  options.mySystem.langlab = {
    enable = lib.mkEnableOption "LangLab language learning server";

    hostname = lib.mkOption {
      type        = lib.types.str;
      description = "Tailscale FQDN (e.g. langlab.vimba-stairs.ts.net)";
    };

    listenPort = lib.mkOption {
      type        = lib.types.int;
      default     = 8080;
      description = "Internal port the server listens on. nginx proxies HTTPS → this port.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── System user ───────────────────────────────────────────────────────────
    users.users.langlab = {
      isSystemUser = true;
      group        = "langlab";
      home         = "/var/lib/langlab";
    };
    users.groups.langlab = {};

    # ── LangLab service ───────────────────────────────────────────────────────
    # Source lives in the Nix store (pinned via flake input); mutable state
    # lives in /var/lib/langlab/ pointed at by LANGLAB_DATA_DIR.
    systemd.services.langlab = {
      description = "LangLab language learning server";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network.target" ];

      serviceConfig = {
        Type            = "simple";
        WorkingDirectory = src;
        ExecStart       = "${pkgs.python3}/bin/python3 ${src}/server.py";

        # API keys from agenix-decrypted EnvironmentFile (KEY=value format).
        # LANGLAB_DATA_DIR and PORT are set inline — no secrets, no rotation needed.
        EnvironmentFile = config.age.secrets.langlab-env.path;
        Environment     = [
          "LANGLAB_DATA_DIR=/var/lib/langlab"
          "PORT=${toString cfg.listenPort}"
        ];

        User  = "langlab";
        Group = "langlab";

        # systemd creates /var/lib/langlab/ owned by the service user.
        StateDirectory     = "langlab";
        StateDirectoryMode = "0750";

        Restart    = "on-failure";
        RestartSec = "5s";
      };
    };

    # ── Tailscale HTTPS certificate ───────────────────────────────────────────
    # Identical pattern to ntfy — certs land in /var/lib/nginx-certs/.
    services.tailscale.permitCertUid = "nginx";

    systemd.services.tailscale-cert = {
      description = "Provision Tailscale TLS cert for nginx";
      after    = [ "tailscaled.service" "network-online.target" "tailscaled-autoconnect.service" ];
      wants    = [ "network-online.target" ];
      before   = [ "nginx.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        Restart         = "on-failure";
        RestartSec      = "30";  # tailscale cert fails with "no netmap" if TS isn't fully up yet
        ExecStart = pkgs.writeShellScript "tailscale-cert" ''
          set -euo pipefail
          mkdir -p ${certDir}
          chmod 711 ${certDir}
          ${pkgs.tailscale}/bin/tailscale cert \
            --cert-file ${certDir}/${cfg.hostname}.crt \
            --key-file  ${certDir}/${cfg.hostname}.key \
            ${cfg.hostname}
          chown root:nginx ${certDir}/${cfg.hostname}.key
          chmod 640        ${certDir}/${cfg.hostname}.key
          chmod 644        ${certDir}/${cfg.hostname}.crt
        '';
      };
    };

    # ── nginx reverse proxy ───────────────────────────────────────────────────
    # recommendedProxySettings sets Host/X-Forwarded-* — do NOT redeclare them.
    services.nginx = {
      enable                 = true;
      recommendedProxySettings = true;
      recommendedTlsSettings  = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."${cfg.hostname}" = {
        sslCertificate    = "${certDir}/${cfg.hostname}.crt";
        sslCertificateKey = "${certDir}/${cfg.hostname}.key";
        forceSSL          = true;

        locations."/" = {
          proxyPass       = "http://127.0.0.1:${toString cfg.listenPort}";
          proxyWebsockets = true;   # tutor view uses fetch streaming
          extraConfig     = "client_max_body_size 200m;";  # allow VTT+MP3 and apkg uploads
        };
      };
    };

    # ── agenix secrets ────────────────────────────────────────────────────────
    # langlab-env is a KEY=value file consumed as systemd EnvironmentFile.
    # Contents (stored in 1Password devops/"LangLab env"):
    #   GEMINI_API_KEY=<key>
    #   CLAUDE_API_KEY=<key>
    age.secrets.langlab-env = {
      file  = ../../secrets/langlab-env.age;
      owner = "langlab";
      mode  = "0400";
    };

    # ── Firewall ──────────────────────────────────────────────────────────────
    # HTTPS only — HTTP (80) intentionally omitted.
    networking.firewall.allowedTCPPorts = [ 443 ];
  };
}
