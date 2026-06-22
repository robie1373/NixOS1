# modules/_system/pages.nix
#
# Static web HOST — infrastructure only. This module stands up nginx to serve a
# directory of static files over plain HTTP on the LAN, and nothing else. It
# deliberately carries NO content: nixos-config owns the webserver, never the
# pages it serves.
#
# Content lives off-repo on the NAS (~/nas/web/pages/) and is pushed to this
# host's local disk at `serveRoot` by `~/nas/web/deploy-pages` (rsync). Keeping
# content out of the flake is the whole point: a future Quartz-rendered view of
# the Ledger ships through the SAME push pipeline, so the Ledger is never baked
# into nixos-config and never reaches GitHub. See ledger [[pages]] and
# inbox/distributed-bearing-architecture.md.
#
# Design decisions:
#   - LAN-first, plain HTTP/80. Content is non-sensitive (running plans); there
#     is no auth and nothing worth a TLS dependency. Reachable at http://<ip>.
#     Tailscale still runs (server-common) for SSH/management — but nothing here
#     DEPENDS on Tailscale. A Tailscale HTTPS vhost can be added later if wanted.
#   - serveRoot is a plain local directory populated out-of-band, NOT a Nix-store
#     path. Deploy copies to LOCAL disk, so serving has no NAS runtime dependency
#     (NAS down != site down — chaos-monkey). After a host wipe, serveRoot is
#     empty (branded 404s) until the next deploy: content is lost, not a service.

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.pages;
in
{
  options.mySystem.pages = {
    enable = lib.mkEnableOption "static page web host (plain HTTP, LAN-first)";

    serveRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/www/pages";
      description = ''
        Local directory nginx serves at the web root. Populated out-of-band by
        the deploy script (~/nas/web/deploy-pages) — NOT baked from the repo.
        Created empty by tmpfiles so nginx starts cleanly before the first deploy.
      '';
    };

    serverNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "pages.home.lab" ];
      description = ''
        Host header(s) that serve the site content. Everything else — including
        an unmapped *.home.lab caught by the DNS catch-all (home.lab -> this host)
        — falls to the default vhost and gets the branded 404, never a search
        engine. Include the LAN IP here too if you want http://<ip> to serve content.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # Ensure the serve root exists (world-readable) even before the first deploy,
    # so nginx starts cleanly and an unprovisioned host shows the branded 404
    # rather than failing. Content is delivered separately by deploy-pages.
    systemd.tmpfiles.rules = [
      "d ${cfg.serveRoot} 0755 root root - -"
    ];

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      # Content vhost — serves the site for its real hostname(s). A 404 on a
      # known host (an unknown *path*) shows the branded 404, not nginx default.
      virtualHosts."pages-content" = {
        serverName = lib.concatStringsSep " " cfg.serverNames;
        root = cfg.serveRoot;
        locations."/" = {
          index = "index.html";
        };
        locations."= /404.html" = {
          extraConfig = "internal;";
        };
        extraConfig = ''
          error_page 404 /404.html;
        '';
      };

      # Default catch-all — any other Host (e.g. an unmapped *.home.lab that the
      # DNS catch-all resolves to this host) gets our branded 404. The goal:
      # "my page or my 404", never a search engine.
      virtualHosts."pages-catchall" = {
        default = true;
        serverName = "_";
        root = cfg.serveRoot;
        locations."/" = {
          extraConfig = "return 404;";
        };
        locations."= /404.html" = {
          extraConfig = "internal;";
        };
        extraConfig = ''
          error_page 404 /404.html;
        '';
      };
    };

    # Only HTTP/80 — no TLS, no other ports. Tailscale traffic is already
    # trusted via server-common (firewall.trustedInterfaces = [ "tailscale0" ]).
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
