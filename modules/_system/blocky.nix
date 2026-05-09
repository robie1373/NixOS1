# modules/_system/blocky.nix
#
# Blocky DNS resolver with ad/malware/tracking blocking.
# Replaces Technitium on dns1/dns2/nixsrv1.
#
# No web UI — all config is declarative here.
# Adding a new local DNS entry: edit localDns map, run `colmena apply --on dns1,dns2,nixsrv1`.
#
# Blocklists refresh every 4h. On first start, Blocky fetches all lists before
# serving queries — takes ~30s with these list sizes. This is normal.

{ config, lib, ... }:

{
  options.mySystem.blocky = {
    enable = lib.mkEnableOption "Blocky DNS resolver with blocking";

    localDns = lib.mkOption {
      type        = lib.types.attrsOf lib.types.str;
      default     = {};
      description = "hostname → IP map for local DNS entries (home.lab zone)";
    };
  };

  config = lib.mkIf config.mySystem.blocky.enable {
    services.blocky = {
      enable   = true;
      settings = {

        # ── Upstream resolvers ──────────────────────────────────────────
        upstreams.groups.default = [
          "https://one.one.one.one/dns-query"   # Cloudflare DoH
          "https://dns.google/dns-query"         # Google DoH
        ];

        # ── Blocking ────────────────────────────────────────────────────
        blocking = {
          blackLists = {
            ads-tracking = [
              # Hagezi Pro — comprehensive ads, tracking, telemetry
              # Format: domain-only (no 0.0.0.0 prefix)
              "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro-onlydomains.txt"
            ];
            nrd = [
              # Hagezi NRD-7 — newly registered domains (last 7 days)
              # High-risk category: most malware uses freshly registered domains
              "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/nrd7.txt"
            ];
            fakenews = [
              # StevenBlack fakenews alternate — fake news, misinformation sources
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
            ];
          };

          # Apply all block categories to all clients by default
          clientGroupsBlock.default = [ "ads-tracking" "nrd" "fakenews" ];

          # Refresh blocklists every 4 hours
          refreshPeriod = "4h";

          # NRD list is large and changes daily — allow failures without stopping service
          downloadAttempts   = 3;
          downloadCooldown   = "5s";
          downloadTimeout    = "60s";
          startStrategy     = "failOnError";
        };

        # ── Local DNS ───────────────────────────────────────────────────
        # home.lab zone — replaces Unbound authoritative on fw post-cutover.
        # Leave empty until fw Unbound is decommissioned; add entries as services migrate.
        customDNS = lib.mkIf (config.mySystem.blocky.localDns != {}) {
          mapping = config.mySystem.blocky.localDns;
        };

        # ── Caching ─────────────────────────────────────────────────────
        caching = {
          minTime     = "5m";
          maxTime     = "30m";
          prefetching = true;
        };

        # ── Logging ─────────────────────────────────────────────────────
        # Warn-only keeps logs manageable. Upgrade to info for debugging.
        # Future: add queryLog.type = loki when Loki stack is deployed.
        log.level = "warn";

        # ── Port ────────────────────────────────────────────────────────
        port = "53";
      };
    };

    networking.firewall.allowedTCPPorts = [ 53 ];
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
