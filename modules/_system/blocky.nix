# modules/_system/blocky.nix
#
# Blocky DNS resolver with ad/malware/tracking blocking.
# Replaces Technitium on dns1/dns2/nixsrv1.
#
# No web UI — all config is declarative here.
# Adding a new local DNS entry: edit localDns map, then deploy with
# `scripts/update-fleet.sh dns1 dns2` (or `nixos-rebuild switch --flake .#dns1 --target-host root@dns1.home.lab`).
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

    dohPort = lib.mkOption {
      type        = lib.types.nullOr lib.types.port;
      default     = null;
      example     = 8443;
      description = ''
        If set, enable Blocky's DoH (HTTPS) listener on this TCP port and open
        the firewall for it. certFile/keyFile are intentionally left empty so
        Blocky self-signs — the public, client-certificate (mTLS) TLS is
        terminated by an external nginx edge that reverse-proxies /dns-query
        here; this internal hop only needs transport encryption. Null = no DoH
        listener (default). Roaming-DoH endpoint design: dns.nixnook.com.
      '';
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
              # Hagezi NRD-7 — newly registered domains (last 7 days).
              # URL updated 2026-07-03: hagezi moved NRD/DGA lists to the
              # dedicated hagezi/nrd repo (issue #10561); old dns-blocklists
              # URLs died 2026-07-01 and crash-looped blocky on restart
              # (failOnError). See ledger blocky.md → NRD incident.
              "https://raw.githubusercontent.com/hagezi/nrd/main/domains/nrd7.txt"
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
        # Per-query visibility: queryLog=console → journald → Alloy →
        # VictoriaLogs on observ. This is the all-nixos-lab Project A gate —
        # bad-block hunts happen in Grafana/LogsQL, replacing Technitium's UI.
        # log.level=info is required: console query-log entries emit at info
        # and warn suppresses them. Volume: one line per query from VLAN 20
        # hosts; VictoriaLogs retention bounds it.
        # (blocky 0.31 has no "loki" queryLog type — the old comment here was
        # aspirational. Valid types: console/sqlite/csv/csv-client/dnstap/
        # mysql/postgresql/timescale/none.)
        log.level = "info";
        queryLog.type = "console";

        # ── Port / IP version ───────────────────────────────────────────
        ports = {
          dns  = 53;
          http = 4000;
        } // lib.optionalAttrs (config.mySystem.blocky.dohPort != null) {
          # DoH listener for the roaming endpoint. Self-signed (certFile/keyFile
          # empty) — the public client-cert TLS is terminated by the nginx edge;
          # this hop is internal. See ledger roaming-doh-design.
          https = ":${toString config.mySystem.blocky.dohPort}";
        };
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

    networking.firewall.allowedTCPPorts =
      [ 53 4000 ] ++ lib.optional (config.mySystem.blocky.dohPort != null) config.mySystem.blocky.dohPort;
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
