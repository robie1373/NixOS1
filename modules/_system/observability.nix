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

  # Lab hosts running node-exporter (VLAN 20). Comment a line to drop a target;
  # a down target shows as up=0 in VictoriaMetrics, which is itself useful signal.
  nodeTargets = [
    "192.168.20.56:9100"  # observ (self)
    "192.168.20.10:9100"  # ntfy
    "192.168.20.11:9100"  # langlab
    "192.168.20.50:9100"  # omada
    "192.168.20.53:9100"  # dns1
    "192.168.20.55:9100"  # nixsrv1
    # "192.168.20.54:9100"  # dns2 — never completed; enable once deployed
  ];

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
        default = [ "192.168.7.40" "192.168.7.159" ];  # pve, pve2
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
            static_configs = [{ targets = nodeTargets; }];
          }
        ] ++ pveScrape;
      };
    };

    # ── Log store ──────────────────────────────────────────────────────────────
    services.victorialogs = {
      enable = true;
      extraOptions = [ "-retentionPeriod=${cfg.retention}" ];
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
        datasources = [
          {
            name = "VictoriaMetrics";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:8428";
            isDefault = true;
          }
          {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            access = "proxy";
            url = "http://127.0.0.1:9428";
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
  };
}
