# modules/_system/langlab.nix
#
# LangLab language learning suite.
# Python stdlib server + SQLite + Gemini AI (lessons, tutor).
# Two users: Robie (Korean) and Anna (Spanish).
#
# Access: plain HTTP on the LAN (same pattern as pages). LAN-only tool on
# VLAN 20; HTTPS returns when the planned VLAN 20 Let's Encrypt reverse
# proxy lands. Until then browser SpeechRecognition (tutor voice input)
# is unavailable — it requires a secure context. TTS is unaffected.
# Secrets: langlab-env.age — EnvironmentFile with GEMINI_API_KEY + CLAUDE_API_KEY.
# State: /var/lib/langlab/ — study.db + languages/ audio files.
# Source: pinned via flake input `langlab` (github:robie1373/langlab).

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.mySystem.langlab;
  src = inputs.langlab;
in
{
  options.mySystem.langlab = {
    enable = lib.mkEnableOption "LangLab language learning server";

    hostname = lib.mkOption {
      type        = lib.types.str;
      description = "LAN FQDN nginx serves (e.g. langlab.home.lab — Blocky localDns zone)";
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

    # ── nginx reverse proxy ───────────────────────────────────────────────────
    # Plain HTTP on the LAN. default = true makes this vhost answer on the
    # bare IP too, so the service works even if a client bypasses DNS.
    # recommendedProxySettings sets Host/X-Forwarded-* — do NOT redeclare them.
    services.nginx = {
      enable                 = true;
      recommendedProxySettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."${cfg.hostname}" = {
        default = true;

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
    # HTTP only — LAN-only tool; TLS returns via the planned VLAN 20 LE proxy.
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
