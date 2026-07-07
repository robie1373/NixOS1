# modules/_system/pages.nix
#
# Static web HOST — infrastructure only. This module stands up nginx to serve a
# directory of static files over plain HTTP on the LAN, and nothing else.
#
# Content model: BAKE (Robie's ruling 2026-07-06, pages-stateless-content).
# Content lives in its own LOCAL git repo (~/proj/pages-content on flipper),
# pinned as the `pages-content` flake input; the serving guest sets serveRoot
# to that store path. Pointer-not-payload: nixos-config (and GitHub) carry only
# the lock hash, never the content — so a future Quartz-rendered Ledger view
# still never reaches GitHub. Content survives guest restarts/wipes because it
# IS part of the closure. The old model (rsync push via ~/nas/web/deploy-pages
# to a mutable /var/www/pages) is RETIRED — it was undeclared state; the guest
# came back 403 after every restart. Publishing protocol: ledger [[pages]].
#
# Design decisions:
#   - LAN-first, plain HTTP/80. Content is non-sensitive (running plans); there
#     is no auth and nothing worth a TLS dependency. Reachable at http://<ip>.
#   - serveRoot may be a store path (baked content — the normal case) or a
#     mutable directory (the tmpfiles rule below only applies then; kept so the
#     vestigial standalone pages host still evals until it's removed).

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
        Directory nginx serves at the web root. Normal case: the pages-content
        flake input's store path (baked content). A non-store path is created
        empty by tmpfiles so nginx starts cleanly (legacy push model).
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

    # For a mutable (non-store) serveRoot only: ensure it exists so nginx starts
    # cleanly. A store-path serveRoot needs (and permits) no creation.
    systemd.tmpfiles.rules = lib.mkIf (!lib.hasPrefix builtins.storeDir cfg.serveRoot) [
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
