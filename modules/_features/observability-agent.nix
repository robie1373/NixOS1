# modules/_features/observability-agent.nix
#
# Per-host telemetry agent for the visibility stack (VictoriaMetrics + Grafana).
# Imported by server-common.nix so every headless lab server ships data with no
# per-host config. Two parts:
#   - node-exporter (:9100) — host metrics, SCRAPED by VictoriaMetrics on observ.
#   - Grafana Alloy         — reads the systemd journal and PUSHES logs to
#                             VictoriaLogs on observ (Loki-compatible ingest API).
#
# Graceful degradation (chaos-monkey): if observ is down, node-exporter still
# serves locally and Alloy buffers/retries. No host depends on observ to boot.
#
# Vendor note: node-exporter + Alloy are the only Grafana-Labs components in the
# data path, and they only MOVE data — the stores (VictoriaMetrics/VictoriaLogs,
# Apache-2.0, bootstrapped) hold it. See ledger vendor-trust.md -> observability.

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.observabilityAgent;
in
{
  options.mySystem.observabilityAgent = {
    enable = lib.mkEnableOption "node-exporter + Alloy log shipping to the visibility stack";

    logsEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://192.168.20.56:9428/insert/loki/api/v1/push";
      description = "VictoriaLogs Loki-push endpoint on the observ host.";
    };

    nodeExporterPort = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port node-exporter listens on; scraped by VictoriaMetrics.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Host metrics ───────────────────────────────────────────────────────────
    services.prometheus.exporters.node = {
      enable = true;
      port = cfg.nodeExporterPort;
      enabledCollectors = [ "systemd" ];
    };

    # node-exporter binds all interfaces; expose the port on the lab network so
    # VictoriaMetrics on observ (VLAN 20) can scrape it. Internal VLAN only.
    networking.firewall.allowedTCPPorts = [ cfg.nodeExporterPort ];

    # ── Log shipping ───────────────────────────────────────────────────────────
    # Alloy reads the journal and pushes to VictoriaLogs. configPath is a plain
    # file; its internal correctness is verified on first deploy, not at eval.
    services.alloy = {
      enable = true;
      configPath = pkgs.writeText "alloy-config.alloy" ''
        // Stamp the hostname and lift a few bounded journal metadata fields into
        // queryable labels (VictoriaLogs stream fields). The journal source
        // exposes each field as __journal__<field>; note the underscore count:
        // a leading underscore on the journal field becomes a double underscore
        // (_SYSTEMD_UNIT -> __journal__systemd_unit, _TRANSPORT -> __journal__transport),
        // no leading underscore stays single (PRIORITY -> __journal_priority).
        // Deliberately bounded/low-cardinality; everything unbounded stays in _msg.
        loki.relabel "journal_labels" {
          forward_to = []
          rule {
            target_label = "host"
            replacement  = "${config.networking.hostName}"
          }
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label  = "unit"
          }
          rule {
            source_labels = ["__journal_priority"]
            target_label  = "priority"
          }
          rule {
            source_labels = ["__journal__transport"]
            target_label  = "transport"
          }
        }

        // Read the systemd journal and forward to the writer.
        loki.source.journal "journal" {
          forward_to    = [loki.write.default.receiver]
          relabel_rules = loki.relabel.journal_labels.rules
          labels        = { job = "systemd-journal" }
        }

        // Push to VictoriaLogs on observ (Loki-compatible ingest API).
        loki.write "default" {
          endpoint {
            url = "${cfg.logsEndpoint}"
          }
        }
      '';
    };
  };
}
