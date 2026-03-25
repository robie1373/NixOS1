# modules/system/ntfy.nix
#
# ntfy push notification server with nginx reverse proxy and Tailscale HTTPS cert.
#
# TLS strategy: Tailscale HTTPS certificates (*.vimba-stairs.ts.net)
#   - Valid Let's Encrypt cert, no self-signed warnings
#   - No public port exposure — Tailscale-only access
#   - No AWS/Route53 credentials needed
#   - Cert managed by tailscaled, nginx reads it via permitCertUid
#
# Auth strategy: local SQLite user database initially.
#   After Kanidm is deployed, migrate to LDAP and remove ntfy-admin-password secret.
#
# Rewrite note: this is a lab-infrastructure module, no desktop concern.

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.ntfy;
in
{
  options.mySystem.ntfy = {
    enable = lib.mkEnableOption "ntfy push notification server";

    hostname = lib.mkOption {
      type = lib.types.str;
      description = "Tailscale hostname for this host (e.g. ntfy.vimba-stairs.ts.net)";
    };

    listenPort = lib.mkOption {
      type = lib.types.int;
      default = 2586;
      description = "Internal port ntfy listens on. nginx proxies HTTPS → this port.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── ntfy-sh ───────────────────────────────────────────────────────────────
    services.ntfy-sh = {
      enable = true;
      settings = {
        # Tailscale HTTPS hostname — used in notification URLs
        base-url = "https://${cfg.hostname}";

        # Listen on localhost only — nginx is the public-facing endpoint
        listen-http = "127.0.0.1:${toString cfg.listenPort}";

        # SQLite message cache — survives hard reboots, enables since= replay
        # SQLite WAL mode (default) is safe against sudden power loss
        cache-file = "/var/lib/ntfy-sh/cache.db";
        cache-duration = "24h";

        # Auth: local user database — deny all by default, explicit grants required
        # Migrate to LDAP (Kanidm) when that service is deployed
        auth-file = "/var/lib/ntfy-sh/user.db";
        auth-default-access = "deny-all";

        # Attachment storage
        attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
        attachment-total-size-limit = "1G";
        attachment-file-size-limit = "15M";
        attachment-expiry-duration = "24h";
      };
    };

    # ── Admin user provisioning ───────────────────────────────────────────────
    # Creates the admin user on first boot using the agenix-decrypted password.
    # The ntfy-admin-password secret contains a bcrypt hash (generate with:
    #   nix run nixpkgs#ntfy-sh -- user add --role=admin admin
    # or htpasswd-style: ntfy user add admin)
    # TODO: remove this block after Kanidm LDAP migration
    systemd.services.ntfy-sh-admin-setup = {
      description = "Provision ntfy admin user";
      after = [ "ntfy-sh.service" ];
      wantedBy = [ "multi-user.target" ];
      # Run once — skip if user already exists
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "ntfy-admin-setup" ''
          if ! ${pkgs.ntfy-sh}/bin/ntfy user list 2>/dev/null | grep -q '^admin '; then
            ${pkgs.ntfy-sh}/bin/ntfy user add \
              --role=admin \
              --password="$(cat ${config.age.secrets.ntfy-admin-password.path})" \
              admin
          fi
        '';
      };
    };

    # ── Tailscale HTTPS certificate ───────────────────────────────────────────
    # Allow nginx to read the Tailscale-managed TLS cert for this host.
    # Tailscale provisions a valid Let's Encrypt cert for <hostname>.ts.net.
    # After joining the tailnet, run: tailscale cert <hostname>
    # (or configure tailscale to auto-provision — see services.tailscale below)
    services.tailscale.permitCertUid = "nginx";

    # ── nginx reverse proxy ───────────────────────────────────────────────────
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."${cfg.hostname}" = {
        # Tailscale cert paths — tailscaled writes these after `tailscale cert`
        sslCertificate = "/var/lib/tailscale/certs/${cfg.hostname}.crt";
        sslCertificateKey = "/var/lib/tailscale/certs/${cfg.hostname}.key";
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.listenPort}";
          proxyWebsockets = true;  # required for ntfy real-time subscriptions
          extraConfig = ''
            # ntfy requires these headers for Web Push and long-poll to work
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            # Allow long-lived connections for ntfy subscriptions
            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
          '';
        };
      };
    };

    # ── agenix secrets ───────────────────────────────────────────────────────
    age.secrets.ntfy-admin-password = {
      file = ../../secrets/ntfy-admin-password.age;
      owner = "ntfy-sh";
      mode = "0400";
    };

    # ── Firewall ─────────────────────────────────────────────────────────────
    # Only HTTPS (443) exposed — HTTP (80) intentionally omitted.
    # ntfy is Tailscale-only; these ports are only reachable on the tailnet.
    networking.firewall.allowedTCPPorts = [ 443 ];
  };
}
