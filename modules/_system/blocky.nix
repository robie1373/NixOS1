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
      description = "hostname → IP map for local DNS entries (home.lab zone)";
      # Single source of truth for the home.lab zone (moved here from per-host
      # copies 2026-07-03 after the dns1/dns2 maps drifted — dns2's copy lacked
      # observ/pages/nas/HA/printer). Every blocky host serves this same map;
      # override per-host only with a deliberate reason.
      default = {
        # Hypervisors
        "vhost1.home.lab" = "192.168.20.40";  # rung 5 (pve → vhost1), 2026-07-17; mgmt on VLAN 20
        "vhost2.home.lab" = "192.168.20.41";  # rung 4 (pve2→vhost2); mgmt moved VLAN10→20 2026-07-05
        # pve/pve2 transition aliases removed 2026-07-17 (Robie's call) — the dead
        # Proxmox names are retired; use vhost1.home.lab/.20.40 + vhost2.home.lab/.20.41.
        # NixOS lab services (VLAN 20)
        "ntfy.home.lab"    = "192.168.20.10";
        # langlab.home.lab — VM decommissioned 2026-07-16 pending redesign; re-add when rebuilt.
        # "langlab.home.lab" = "192.168.20.11";
        "omada.home.lab"   = "192.168.20.134"; # OC200 hardware appliance (was .20.50 microVM, retired 2026-07-16)
        "dns1.home.lab"    = "192.168.20.53";
        "dns2.home.lab"    = "192.168.20.54";
        "dns3.home.lab"    = "192.168.20.55";
        "nixsrv1.home.lab" = "192.168.20.55";
        "observ.home.lab"  = "192.168.20.56";
        "pages.home.lab"   = "192.168.20.57";
        "git.home.lab"     = "192.168.20.58";
        # NAS
        "nas.home.lab"     = "192.168.20.12";
        # Legacy Ubuntu services (VLAN 10 — update IPs as services migrate to VLAN 20)
        # karakeep/nginx/habla removed 2026-07-04 (all-nixos-lab rung 1 retirement, Opus 4.8) —
        # hosts destroyed; names now fall through to the pages catch-all below.
        "director.home.lab" = "192.168.7.58";
        # Infrastructure (VLAN 10)
        "home-assistant.home.lab" = "192.168.7.56";
        "printer.home.lab"        = "192.168.7.104";

        # Catch-all — Blocky resolves subdomains of a mapping, so this maps every
        # UNMAPPED *.home.lab (and bare home.lab) to the pages host, whose default
        # vhost returns a branded 404. Explicit entries above are more specific and
        # win. Net effect: any home.lab name is either a real service or *our* 404 —
        # never a search engine. (Verified 2026-06-22: sub.nas.home.lab -> nas IP.)
        "home.lab" = "192.168.20.57";
      };
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
        # ── Upstream init behaviour ─────────────────────────────────────
        # `fast` (was the default `blocking`, changed 2026-08-17, Robie's call).
        #
        # THIS IS THE SAME TRAP AS THE BLOCKLIST strategy=fast FIX BELOW, in a
        # different subsystem. With `blocking`, blocky refuses to start until it can
        # resolve its DoH upstream hostnames (one.one.one.one, dns.google). During a
        # WAN outage that resolution fails — and so does bootstrapDns, because
        # 1.1.1.1/8.8.8.8 are also unreachable when the edge is down. Net effect: a
        # blocky restart while the ISP is down leaves NO DNS AT ALL, including
        # `home.lab`, which is the one thing that kept working during the 2026-08-17
        # outage. That restart is reachable: a patch day, or Robie power-cycling gear
        # while troubleshooting the ISP.
        #
        # `fast` serves immediately and resolves upstreams in the background. Local
        # zones (customDNS) answer with no WAN whatsoever. Degraded, never dead.
        upstreams.init.strategy = "fast";

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
            canary = [
              # Inline list (newline forces blocky's inline detection). The
              # alerting spine's weekly probe digs this always-blocked, never-
              # legitimate name; the resulting BLOCKED query-log line fires the
              # SpineWeeklyProbe vlogs rule (green phone ping). Chosen after
              # learning blocky does NOT block subdomains of list entries
              # (2026-07-04) — an owned exact entry beats guessing at lists.
              ''
                spine-probe.canary
              ''
            ];
          };

          # Apply all block categories to all clients by default
          clientGroupsBlock.default = [ "ads-tracking" "nrd" "fakenews" "canary" ];

          # blocky 0.29 moved these under blocking.loading.*
          loading = {
            refreshPeriod = "4h";
            # fast (was failOnError, changed 2026-07-03, Robie's call): post-repoint
            # dns1/dns2 are the ONLY upstreams and identical configs make dead-list
            # URLs a correlated crash-loop (see ledger blocky.md, NRD incident).
            # fast = serve immediately, load lists in background; a failed list is
            # degraded blocking, never no-DNS. Also closes the cold-boot race.
            # List-failure visibility moves to observ (Grafana→ntfy alerting task).
            strategy      = "fast";
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

        # ── Metrics ─────────────────────────────────────────────────────
        # Prometheus metrics on the existing :4000 HTTP listener (/metrics).
        # Scraped by VictoriaMetrics on observ (job "blocky") — rate/block/cache
        # graphs for the Technitium-retirement soak and beyond.
        prometheus.enable = true;

        # ── Caching ─────────────────────────────────────────────────────
        # Retuned 2026-08-17 (Robie) for WAN-outage survivability. The semantics are
        # counterintuitive and were initially got backwards, so per blocky's own docs:
        #   minTime — "if >0 use this value, IF TTL IS SMALLER"  → a FLOOR
        #   maxTime — "if >0, use this value, IF TTL IS GREATER" → a CAP
        # So maxTime only touches records whose TTL already exceeds it, and the names
        # that matter in an outage (Dropbox, GitHub, nixos.org) are CDN-fronted with
        # 60–300s TTLs. **minTime is the lever that actually extends their cache life.**
        caching = {
          # 5m → 1h. Every response is held at least an hour regardless of its TTL,
          # so a short outage is invisible for anything queried in the last hour.
          # Evidence this was the binding constraint: the cache held only ~190 entries
          # at a 66% hit rate while maxItemsCount is unlimited — entries were expiring,
          # not being evicted.
          #
          # ⚠️ TRADE-OFF, deliberate: DNS-based failover for external services is not
          # followed for up to an hour. If a provider moves an endpoint mid-outage-free
          # day, we chase it late. Acceptable for a homelab; dial back toward 15–30m if
          # anything ever appears to be pinned to a dead IP.
          minTime     = "1h";
          # 30m → 24h. Secondary — only helps the minority of records with long TTLs.
          maxTime     = "24h";
          # Default is 30m, and "negative" includes EMPTY RESULTS, not just NXDOMAIN.
          # At 30m a failure recorded during an outage keeps being served for half an
          # hour after the WAN returns — the outage outliving the outage. 1m keeps the
          # anti-hammering benefit while making recovery essentially immediate.
          cacheTimeNegative = "1m";
          prefetching = true;
          # Widen the window (default 2h) and lower the bar (default 5) so more of the
          # working set stays warm and therefore survives. Prefetching already earns
          # 25k/69k hits on dns1/dns2, so this is amplifying something that works.
          prefetchExpires   = "4h";
          prefetchThreshold = 3;
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
