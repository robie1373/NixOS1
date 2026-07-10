# modules/_system/observability.nix
#
# Server side of the visibility stack. Runs on the `observ` host only.
#   - VictoriaMetrics (:8428) — metrics TSDB; scrapes node-exporters + pve-exporter.
#   - VictoriaLogs    (:9428) — log store; receives Alloy pushes (Loki API).
#   - Grafana         (:3000) — dashboards; datasources provisioned below.
#   - pve-exporter    (:9221) — OPTIONAL; queries Proxmox API for pve/pve2 metrics.
#
# Retention is deliberately short (10d) — this stack is for short-term
# troubleshooting, not capacity trends. See TASKS.md visibility item.
#
# Vendor posture: the data layer (VictoriaMetrics/VictoriaLogs) is Apache-2.0 and
# bootstrapped. Grafana (VC-backed/AGPL) is the swappable dashboard layer only;
# it stores nothing proprietary. See ledger vendor-trust.md -> observability.

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.observability;

  # Lab hosts running node-exporter, pulled over VLAN 20. Each carries a `host`
  # label so metrics line up with the logs (Alloy stamps `host`) and with the
  # pushed hosts (pve/pve2 set host via vmagent external_labels). Comment a line
  # to drop a target; a down target shows as up=0, which is itself useful signal.
  nodeTargets = [
    { host = "observ";  addr = "192.168.20.56:9100"; }
    { host = "ntfy";    addr = "192.168.20.10:9100"; }
    { host = "langlab"; addr = "192.168.20.11:9100"; }
    # omada — RETIRED as a scrape target 2026-07-09: migrated to the OC200 hardware
    # appliance, and the microVM is now a stopped rollback (autostart=false). An
    # appliance runs no node-exporter, and the OC200 (.134) answers no SNMP either
    # (timed out) — its only signals are ICMP reachability + syslog (app_name="Omada",
    # already flowing to VL). Scraping the stopped .50 would just page InstanceDown.
    # To put OC200 liveness on the board, build a blackbox ICMP probe (TASKS #44).
    # { host = "omada";   addr = "192.168.20.50:9100"; }
    { host = "dns1";    addr = "192.168.20.53:9100"; }
    { host = "dns2";    addr = "192.168.20.54:9100"; }  # deployed 2026-07-03 (all-nixos-lab Project A)
    { host = "pages";   addr = "192.168.20.57:9100"; }
    # vhost2 — NixOS hypervisor (all-nixos-lab rung 4, formerly pve2). Mgmt moved
    # VLAN 10 (.7.159) → VLAN 20 (.20.41) on 2026-07-05, so this scrape is now
    # SAME-VLAN as observ. Replaces pve2's old pve-exporter/vmagent-push path (D9).
    { host = "vhost2";  addr = "192.168.20.41:9100"; }
    # fw is the edge router (OPNsense/FreeBSD), pulled on its VLAN-20 leg (.254).
    # Needs os-node_exporter on fw AND a LAB-interface allow rule for observ→.254:9100
    # (fw blocks lab→RFC1918 by default, same as the explicit :53 pass). Shows up=0
    # until both are in place. Logs come via syslog (udp/514→1514), not this scrape.
    { host = "fw";      addr = "192.168.20.254:9100"; }
    # { host = "nixsrv1"; addr = "192.168.20.55:9100"; }  # NOT deployed (KDE/installer, no reservation, 2026-06-18) — phantom up=0; re-enable when nixsrv1 is a real server. See [[homelab]].
  ];

  # Blocky DNS resolvers — native metrics on the :4000 HTTP listener (/metrics;
  # prometheus.enable in modules/_system/blocky.nix). Same host-label convention
  # as the node job so DNS metrics join the $host dashboard variable.
  blockyScrape = [{
    job_name = "blocky";
    static_configs = [
      { targets = [ "192.168.20.53:4000" ]; labels = { host = "dns1"; }; }
      { targets = [ "192.168.20.54:4000" ]; labels = { host = "dns2"; }; }
    ];
  }];

  # PVE scrape job (only when the exporter is enabled). Standard pve-exporter
  # relabel: pass each target as ?target=<node>, send the request to the local
  # exporter, keep the node address as the instance label.
  pveScrape = lib.optionals cfg.pveExporter.enable [{
    job_name = "pve";
    metrics_path = "/pve";
    params.module = [ "default" ];
    static_configs = [{ targets = cfg.pveExporter.nodes; }];
    relabel_configs = [
      { source_labels = [ "__address__" ]; target_label = "__param_target"; }
      { source_labels = [ "__param_target" ]; target_label = "instance"; }
      { target_label = "__address__"; replacement = "127.0.0.1:9221"; }
    ];
  }];

  # SNMP scrape jobs for the Omada fabric (switch + EAP773 APs). snmp_exporter
  # runs on loopback (:9116). Standard snmp_exporter relabel: pass the device IP
  # as ?target=, send the request to the local exporter, keep the device IP as
  # the instance label. The `host` label matches the fleet convention so device
  # metrics join the $host dashboard variable. Switch has no PoE MIB, so just
  # if_mib+system; APs add the TP-Link `eap` module (client counts).
  snmpRelabel = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "127.0.0.1:9116"; }
  ];
  snmpScrape = [
    {
      job_name = "snmp-switch";
      metrics_path = "/snmp";
      params = { auth = [ "omada_v2" ]; module = [ "if_mib" "system" ]; };
      static_configs = [{ targets = [ "192.168.20.145" ]; labels = { host = "coreswitch"; }; }];
      relabel_configs = snmpRelabel;
    }
    {
      job_name = "snmp-ap";
      metrics_path = "/snmp";
      params = { auth = [ "omada_v2" ]; module = [ "eap" "system" "if_mib" ]; };
      static_configs = [
        { targets = [ "192.168.20.180" ]; labels = { host = "ap-lowerlevel"; }; }
        { targets = [ "192.168.20.182" ]; labels = { host = "ap-mainfloor"; }; }
      ];
      relabel_configs = snmpRelabel;
    }
  ];
in
{
  options.mySystem.observability = {
    enable = lib.mkEnableOption "the visibility stack server (VictoriaMetrics + VictoriaLogs + Grafana)";

    retention = lib.mkOption {
      type = lib.types.str;
      default = "10d";
      description = "Retention for both metrics and logs. Short by design.";
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File providing Grafana's secret_key. When null (default), a random key is
        generated on the host at first boot — fine for a declaratively-provisioned,
        redeploy-disposable Grafana, but NOT durable across a rebuild. Point this
        at an agenix secret (sourced from 1Password) to make the key stable, so a
        persisted Grafana DB (hand-built dashboards/alerts) survives redeploys.
      '';
    };

    pveExporter = {
      enable = lib.mkEnableOption "Proxmox VE exporter (needs a PVE API token secret)";
      nodes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "192.168.7.40" ];  # pve (pve2 removed — converted to vhost2, rung 4, 2026-07-05)
        description = "Proxmox node addresses to scrape via the PVE API.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Metrics store + scraper ────────────────────────────────────────────────
    services.victoriametrics = {
      enable = true;
      retentionPeriod = cfg.retention;
      prometheusConfig = {
        global.scrape_interval = "30s";
        scrape_configs = [
          {
            job_name = "victoriametrics";
            static_configs = [{ targets = [ "127.0.0.1:8428" ]; }];
          }
          {
            job_name = "node";
            static_configs = map (t: {
              targets = [ t.addr ];
              labels = { host = t.host; };
            }) nodeTargets;
          }
        ] ++ blockyScrape ++ pveScrape ++ snmpScrape;
      };
    };

    # ── Log store ──────────────────────────────────────────────────────────────
    services.victorialogs = {
      enable = true;
      extraOptions = [
        "-retentionPeriod=${cfg.retention}"
        # Native syslog listener for the Omada fabric (switch + APs push here
        # directly; controller-independent). Listens on UNPRIVILEGED udp/1514 — the
        # well-known 514 is redirected here by the firewall (below). VictoriaLogs is a
        # hardened non-root DynamicUser and can't bind <1024: granting it
        # CAP_NET_BIND_SERVICE via the unit did NOT work (the cap shows in the unit but
        # the udp/514 bind still returns EACCES; the service's SystemCallFilter sandbox
        # appears to strip the ambient cap before exec — root cause not isolated). Using
        # an unprivileged port + a 514→1514 redirect sidesteps the privileged-port
        # problem entirely and, deliberately, also catches FUTURE log sources that can
        # only emit to the well-known 514 (Robie's call — the redirect is the durable seam).
        #
        # Device logs carry the device-sent `hostname` (CoreSwitch / LowerLevel-AP1 / …),
        # a normal queryable field — NOT the journald/Alloy `host`. useLocalTimestamp
        # guards against bad device clocks. PRI severity here is the device's own
        # (filter on `severity`), not the journald 0–7 `priority`.
        # (streamFields to promote `hostname` to a stream label was dropped: the
        #  victorialogs module double-quotes the JSON-array value and VL rejects it;
        #  hostname is fully queryable as a plain field regardless.)
        "-syslog.listenAddr.udp=:1514"
        "-syslog.useLocalTimestamp.udp=true"
        # Adds a `remote_ip` field with the sender's address. NOTE (2026-06-19): the
        # syslog is RELAYED BY THE OMADA CONTROLLER (remote_ip is always 192.168.20.50,
        # app_name=omada-homeLab), NOT sent device-direct — so this is the controller,
        # not the switch/AP. Per-device identity is only in the `_msg` body
        # ([switch:CoreSwitch:MAC] …). Kept as a source breadcrumb. (Unlike SNMP metrics,
        # which ARE device-direct/controller-independent, device logs depend on the
        # controller being up — an Omada-SDN limitation, see ledger visibility-stack.md.)
        "-syslog.useRemoteIP.udp=true"
      ];
    };

    # ── Network fabric (Omada switch + APs) — SNMP metrics exporter ─────────────
    # Polls the switch + APs via SNMPv2c and exposes Prometheus metrics on loopback
    # (:9116, scraped by the snmpScrape jobs above — no firewall port needed). The
    # config is delivered whole via agenix (snmp-config.age = modules/_system/snmp.yml
    # with the community baked in) because snmp_exporter 0.30.1's runtime env-var
    # expansion does NOT substitute the community (verified 2026-06-19). configurationPath
    # points at the decrypted runtime path; enableConfigCheck is off because that path
    # doesn't exist at build time (the build-time --dry-run can't read it).
    services.prometheus.exporters.snmp = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9116;
      enableConfigCheck = false;
      configurationPath = config.age.secrets.snmp-config.path;
    };

    # ── Proxmox exporter (optional) ────────────────────────────────────────────
    services.prometheus.exporters.pve = lib.mkIf cfg.pveExporter.enable {
      enable = true;
      port = 9221;
      # Env file provides PVE_USER / PVE_TOKEN_NAME / PVE_TOKEN_VALUE / PVE_VERIFY_SSL.
      # Create via agenix — see docs/observability/build-runbook.md.
      environmentFile = config.age.secrets.pve-exporter-token.path;
    };
    age.secrets = {
      # Owned by grafana so the service can read it ($__file). agenix defaults
      # to root:root 0400, which Grafana (user grafana) can't read.
      grafana-admin-pass = {
        file = ../../secrets/grafana-admin-pass.age;
        owner = "grafana";
        group = "grafana";
      };
      # Whole snmp_exporter config (community baked in). Read by the exporter's
      # DynamicUser (snmp-exporter) at runtime via configurationPath; that user
      # doesn't exist at agenix-activation time, so make it world-readable (0444)
      # rather than chown. Acceptable: a read-only SNMP community on the mgmt VLAN,
      # on a single-purpose monitoring VM.
      snmp-config = {
        file = ../../secrets/snmp-config.age;
        mode = "0444";
      };
    } // lib.optionalAttrs cfg.pveExporter.enable {
      pve-exporter-token.file = ../../secrets/pve-exporter-token.age;
    };

    # ── Dashboards ─────────────────────────────────────────────────────────────
    services.grafana = {
      enable = true;
      # VictoriaLogs datasource plugin (signed, from nixpkgs) so logs are
      # queryable in Grafana Explore alongside metrics — job #3, forensics.
      declarativePlugins = [ pkgs.grafanaPlugins.victoriametrics-logs-datasource ];
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 3000;
          domain = "observ.home.lab";
        };
        # No telemetry — vendor posture.
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };
        # secret_key encrypts secrets in Grafana's DB. NixOS 26.05 dropped the
        # default, so it must be set. Default: generated on the host at first boot
        # (grafana-secret-key oneshot below) — never committed to git, but not
        # durable across a redeploy. Set mySystem.observability.secretKeyFile to
        # an agenix/op-backed file to make it stable. See the build runbook.
        security.secret_key =
          if cfg.secretKeyFile != null
          then "$__file{${toString cfg.secretKeyFile}}"
          else "$__file{/var/lib/grafana-secret/secret_key}";
        # Admin password from agenix (1Password devops/"grafana - homelab"),
        # so it's durable across redeploys. Grafana resets the admin user's
        # password to this value on startup.
        security.admin_password = "$__file{${config.age.secrets.grafana-admin-pass.path}}";
      };
      provision.datasources.settings = {
        apiVersion = 1;
        # Drop the pre-existing (auto-UID) datasources first so they're recreated with
        # the pinned UIDs below. Grafana refuses to change the uid of an existing
        # provisioned datasource ("data source not found" → crash-loop) without this.
        # Harmless to keep: runs each start, delete-then-recreate is idempotent.
        deleteDatasources = [
          { name = "VictoriaMetrics"; orgId = 1; }
          { name = "VictoriaLogs"; orgId = 1; }
        ];
        datasources = [
          {
            name = "VictoriaMetrics";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:8428";
            isDefault = true;
            # Pinned UID — the provisioned dashboards (below) reference it. Without a
            # fixed UID, a fresh Grafana assigns a random one and the dashboards would
            # point at nothing after a reimage.
            uid = "victoriametrics";
          }
          {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            access = "proxy";
            url = "http://127.0.0.1:9428";
            uid = "victorialogs";
          }
        ];
      };

      # Dashboards as code — JSON checked into grafana-dashboards/, provisioned into
      # the existing "homeLab" folder (pinned by UID so a fresh Grafana reuses it).
      # Reimage-proof: survives a full host rebuild, not just nixos-rebuild. Exported
      # from the hand-built originals 2026-06-19 with datasource refs rewritten to the
      # pinned UIDs above. allowUiUpdates keeps UI editing usable — but UI edits live in
      # the DB and revert to this JSON on reimage, so re-export to keep them durable.
      provision.dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "homelab";
            type = "file";
            folder = "homeLab";
            folderUid = "cfpjeo6fx4hs0f";
            allowUiUpdates = true;
            updateIntervalSeconds = 30;
            options = {
              path = ./grafana-dashboards;
              foldersFromFilesStructure = false;
            };
          }
        ];
      };
    };

    # Generate Grafana's secret_key on the host at first boot (random, persisted),
    # so nothing secret lands in git or the nix store. The grafana system user
    # exists at activation, before services start, so the chown is safe.
    # Skipped when an explicit secretKeyFile (op-backed) is provided.
    systemd.services.grafana-secret-key = lib.mkIf (cfg.secretKeyFile == null) {
      wantedBy   = [ "multi-user.target" ];
      before     = [ "grafana.service" ];
      requiredBy = [ "grafana.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        dir=/var/lib/grafana-secret
        mkdir -p "$dir"
        if [ ! -s "$dir/secret_key" ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 32 > "$dir/secret_key"
        fi
        chmod 0400 "$dir/secret_key"
        chown grafana:grafana "$dir/secret_key"
      '';
    };

    # Grafana UI (3000) + VictoriaLogs ingest (9428) + VictoriaMetrics (8428,
    # for remote_write push from off-VLAN hosts like pve/pve2 that can't be
    # pulled across the firewall — see [[tailscale]]/[[visibility-stack]] transport).
    # NOTE: 8428 exposes the full VM HTTP API to the lab net; acceptable on the
    # internal VLAN. Harden later with vmauth or a source-scoped rule if needed.
    networking.firewall.allowedTCPPorts = [ 3000 8428 9428 ];
    # Syslog lands on udp/1514 (post-redirect — see below). Devices send to 514;
    # the nat PREROUTING redirect rewrites the dport to 1514 before the filter INPUT
    # check, so it's 1514 that must be allowed here, not 514.
    networking.firewall.allowedUDPPorts = [ 1514 ];

    # Redirect the well-known syslog port udp/514 → udp/1514 so any sender (the Omada
    # devices, and future log sources that can only emit to 514) reaches VictoriaLogs
    # while it binds an unprivileged port as a hardened non-root service. The redirect
    # runs in-kernel (nat PREROUTING) and preserves the source IP. IPv4 only — the lab
    # mgmt fabric is v4. (observ uses the default iptables-based scripted firewall.)
    networking.firewall.extraCommands = ''
      iptables -t nat -A PREROUTING -p udp --dport 514 -j REDIRECT --to-ports 1514
    '';
    networking.firewall.extraStopCommands = ''
      iptables -t nat -D PREROUTING -p udp --dport 514 -j REDIRECT --to-ports 1514 2>/dev/null || true
    '';
  };
}
