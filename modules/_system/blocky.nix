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

        # ── Bootstrap DNS ───────────────────────────────────────────────
        # Plain-IP resolvers used only to resolve DoH upstream hostnames
        # (one.one.one.one, dns.google) on startup. Without this, blocky
        # tries to use the system resolver — which is itself — and fails.
        bootstrapDns = [
          "tcp+udp:1.1.1.1"
          "tcp+udp:8.8.8.8"
        ];

        # ── Upstream resolvers ──────────────────────────────────────────
        upstreams.groups.default = [
          "https://one.one.one.one/dns-query"   # Cloudflare DoH
          "https://dns.google/dns-query"         # Google DoH
        ];

        # ── Blocking ────────────────────────────────────────────────────
        blocking = {
          denylists = {
            ads-tracking = [
              # Hagezi Pro — comprehensive ads, tracking, telemetry
              # GitHub raw: bypass jsDelivr CDN which rate-limits and serves garbage 429 bodies
              # that blocky parses as empty lists (failOnError doesn't catch content-level failures)
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro-onlydomains.txt"
            ];
            nrd = [
              # Hagezi NRD-7 — newly registered domains (last 7 days)
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/nrd7.txt"
            ];
            fakenews = [
              # StevenBlack fakenews alternate
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
            ];
          };

          # Apply all block categories to all clients by default
          clientGroupsBlock.default = [ "ads-tracking" "nrd" "fakenews" ];

          # blocky 0.29 moved these under blocking.loading.*
          loading = {
            refreshPeriod = "4h";
            strategy      = "failOnError";
            downloads = {
              attempts  = 3;
              cooldown  = "5s";
              timeout   = "60s";
            };
          };
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

        # ── Port / IP version ───────────────────────────────────────────
        ports.dns  = 53;
        ports.http = 4000;
        # Force IPv4 only — VMs on VLAN 20 have no IPv6 routing
        connectIPVersion = "v4";
      };
    };

    # Don't start blocky until the network is actually reachable. Without this,
    # on a cold boot blocky races the default route: bootstrap DNS can't reach
    # 1.1.1.1/8.8.8.8, every blocklist download fails, and `strategy=failOnError`
    # takes DNS down. Ordering after network-online.target closes the race while
    # keeping the deliberate fail-visible strategy. See ledger blocky.md
    # "Open issue (2026-06-14)".
    systemd.services.blocky = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    networking.firewall.allowedTCPPorts = [ 53 4000 ];
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
