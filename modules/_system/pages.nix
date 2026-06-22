# modules/_system/pages.nix
#
# Static web host. Serves a directory of self-contained HTML files over plain
# HTTP on the LAN. No backend, no proxy, no app — deliberately. This host exists
# to serve static pages and nothing else; resist the urge to bolt services onto
# it (that muddies a single-purpose box — the whole reason it was stood up).
#
# Design decisions (see ledger inbox/distributed-bearing-architecture.md →
# "Decision 2026-06-22"):
#   - LAN-first, plain HTTP/80. Content is non-sensitive (running plans); there is
#     no auth and nothing worth a TLS dependency. Reachable at http://<host-ip>.
#     Tailscale still runs (server-common) for SSH/management — but nothing here
#     DEPENDS on Tailscale being up (chaos-monkey). A Tailscale HTTPS vhost can be
#     added later as a bonus path, mirroring modules/_system/ntfy.nix, if wanted.
#   - Content is baked into the Nix store from `contentRoot`, so a redeploy
#     reproduces the site exactly — no mutable /var/www to back up or lose.
#     To add a page: drop the file in the host's www/ dir and rebuild.
#   - Future: this is the intended home for a Quartz-rendered, browsable view of
#     the Ledger (markdown stays canonical; HTML is a generated build artifact).

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.pages;
in
{
  options.mySystem.pages = {
    enable = lib.mkEnableOption "static page web host (plain HTTP, LAN-first)";

    contentRoot = lib.mkOption {
      type = lib.types.path;
      description = ''
        Directory of static files served at the web root. Copied into the Nix
        store at build time, so the served content is reproducible on redeploy.
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

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      # Content vhost — serves the site for its real hostname(s). A 404 on a
      # known host (an unknown *path*) shows the branded 404, not nginx default.
      virtualHosts."pages-content" = {
        serverName = lib.concatStringsSep " " cfg.serverNames;
        root = cfg.contentRoot;
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
        root = cfg.contentRoot;
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
