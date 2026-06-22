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

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "_";
      description = ''
        nginx server_name. Default "_" is the catch-all default vhost, so the
        site answers on the host's LAN IP regardless of Host header.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts.${cfg.serverName} = {
        default = true;
        root = cfg.contentRoot;
        locations."/" = {
          index = "index.html";
        };
      };
    };

    # Only HTTP/80 — no TLS, no other ports. Tailscale traffic is already
    # trusted via server-common (firewall.trustedInterfaces = [ "tailscale0" ]).
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
