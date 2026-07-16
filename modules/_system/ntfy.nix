# modules/system/ntfy.nix
#
# ntfy push notification server with nginx reverse proxy and Tailscale HTTPS cert.
#
# TLS strategy: Tailscale HTTPS certificates (*.vimba-stairs.ts.net)
#   - Valid Let's Encrypt cert, no self-signed warnings
#   - No public port exposure — Tailscale-only access
#   - No AWS/Route53 credentials needed
#   - tailscale cert writes to /var/lib/nginx-certs/ (a path we own);
#     Tailscale's own state dir (/var/lib/tailscale/) is never touched.
#
# Auth strategy: local SQLite user database initially.
#   After Kanidm is deployed, migrate to LDAP and remove ntfy-admin-password secret.
#
# Rewrite note: this is a lab-infrastructure module, no desktop concern.

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.ntfy;
  certDir = "/var/lib/nginx-certs";
in
{
  options.mySystem.ntfy = {
    enable = lib.mkEnableOption "ntfy push notification server";

    tls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Serve the Tailscale-cert HTTPS vhost (VM-era default). false = LAN-only:
        plain-HTTP ntfy-lan vhost only, base-url http://, no tailscale-cert
        service. Added 2026-07-16 (rung 5 — Tailscale is dead; the phone
        subscribes to http://ntfy.home.lab).
      '';
    };

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
        # Public hostname — used in notification URLs (scheme follows cfg.tls)
        base-url = "${if cfg.tls then "https" else "http"}://${cfg.hostname}";

        # Relay push notifications through ntfy.sh → APNs/Firebase.
        # Without this, iOS/Android only receive messages when the app is open
        # and polling. With it, ntfy.sh delivers the push wake-up and the app
        # fetches the message from this server.
        upstream-base-url = "https://ntfy.sh";

        # Listen on localhost only — nginx is the public-facing endpoint
        listen-http = "127.0.0.1:${toString cfg.listenPort}";

        # SQLite message cache — survives hard reboots, enables since= replay
        # SQLite WAL mode (default) is safe against sudden power loss
        cache-file = "/var/lib/ntfy-sh/cache.db";
        cache-duration = "24h";

        # Auth: local user database for admin management.
        # Default access is read-write — Tailscale-only service, low friction preferred.
        # Migrate to LDAP (Kanidm) when that service is deployed
        auth-file = "/var/lib/ntfy-sh/user.db";
        auth-default-access = "read-write";

        # Attachment storage
        attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
        attachment-total-size-limit = "1G";
        attachment-file-size-limit = "15M";
        attachment-expiry-duration = "24h";
      };
    };

    # ── Admin user provisioning ───────────────────────────────────────────────
    # Creates the admin user on first boot using the agenix-decrypted password.
    # Uses --ignore-exists so it is safe to re-run on every nixos-rebuild.
    # Password is fed via stdin — ntfy user add does not accept a --password flag.
    # TODO: remove this block after Kanidm LDAP migration
    systemd.services.ntfy-sh-admin-setup = {
      description = "Provision ntfy admin user";
      after = [ "ntfy-sh.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "ntfy-admin-setup" ''
          # ntfy user add prompts for password then confirm — pipe it twice.
          # --ignore-exists makes this idempotent across rebuilds.
          password="$(cat ${config.age.secrets.ntfy-admin-password.path})"
          printf '%s\n%s\n' "$password" "$password" | \
            ${pkgs.ntfy-sh}/bin/ntfy user add \
              --role=admin \
              --ignore-exists \
              admin
        '';
      };
    };

    # ── Tailscale HTTPS certificate ───────────────────────────────────────────
    # tailscale cert fetches a valid Let's Encrypt cert for this host's TS FQDN.
    # Certs are written to /var/lib/nginx-certs/ — a path we own — so nginx can
    # read them without any changes to Tailscale's state directory permissions.
    # The service re-runs on each boot; tailscale cert is a no-op if the cert is
    # still valid, so the copy is cheap.
    services.tailscale.permitCertUid = lib.mkIf cfg.tls "nginx";

    systemd.services.tailscale-cert = lib.mkIf cfg.tls {
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
          # Write to a path we own — never touch /var/lib/tailscale/
          mkdir -p ${certDir}
          chmod 711 ${certDir}
          ${pkgs.tailscale}/bin/tailscale cert \
            --cert-file ${certDir}/${cfg.hostname}.crt \
            --key-file  ${certDir}/${cfg.hostname}.key \
            ${cfg.hostname}
          # nginx must read the key; cert is already world-readable from tailscale
          chown root:nginx ${certDir}/${cfg.hostname}.key
          chmod 640        ${certDir}/${cfg.hostname}.key
          chmod 644        ${certDir}/${cfg.hostname}.crt
        '';
      };
    };

    # ── nginx reverse proxy ───────────────────────────────────────────────────
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."${cfg.hostname}" = lib.mkIf cfg.tls {
        sslCertificate    = "${certDir}/${cfg.hostname}.crt";
        sslCertificateKey = "${certDir}/${cfg.hostname}.key";
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.listenPort}";
          proxyWebsockets = true;  # required for ntfy real-time subscriptions
          extraConfig = ''
            # Allow long-lived connections for ntfy subscriptions (Web Push, long-poll).
            # Note: Host/X-Forwarded-* headers are already set by recommendedProxySettings;
            # do NOT redeclare them here — duplicate Host headers cause ntfy (Go HTTP) to
            # return 400 Bad Request per RFC 7230 §5.4.
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

    # ── LAN-internal plain-HTTP listener (added 2026-07-03, alerting spine) ──
    # Internal publishers (observ's alert bridge; future lab services) must not
    # depend on Tailscale (standing rule; TS is being decommissioned). This vhost
    # gives them an owned LAN path: the VM's one NIC is on VLAN 20, and fw policy
    # keeps guest/iot away from RFC1918. The phone's HTTPS/tailnet vhost above is
    # unchanged. Topic-name obscurity remains the access model, same as before
    # (auth-default-access = read-write) — the audience just widens from tailnet
    # to house-LAN.
    services.nginx.virtualHosts."ntfy-lan" = {
      serverName = "ntfy.home.lab";
      default = true;
      listen = [ { addr = "0.0.0.0"; port = 80; } ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.listenPort}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 3600;
          proxy_send_timeout 3600;
        '';
      };
    };

    # ── Firewall ─────────────────────────────────────────────────────────────
    # 443 = HTTPS (tailnet vhost); 80 = LAN-internal publisher path (above).
    networking.firewall.allowedTCPPorts = [ 443 80 ];
  };
}
