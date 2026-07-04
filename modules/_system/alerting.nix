# modules/_system/alerting.nix
#
# The alerting spine (observ host): vmalert → Alertmanager → ntfy bridge → phone.
#
#   vmalert       — evaluates the rule pack against VictoriaMetrics (:8428).
#                   VictoriaMetrics-native (Apache-2.0); rules live HERE, in the
#                   repo, not in Grafana's DB — Grafana stays the swappable,
#                   stores-nothing dashboard layer (see observability.nix header).
#   Alertmanager  — dedup/grouping/repeat-interval/resolved-notifications.
#                   Loopback-only; nothing else talks to it.
#   ntfy bridge   — ~60 lines of stdlib Python: accepts Alertmanager webhooks on
#                   loopback, formats, POSTs to ntfy over the LAN (never the
#                   tailnet — standing rule; see ntfy.nix "ntfy-lan" vhost).
#                   Topic comes from the agenix secret at runtime.
#
# Delivery contract: alerts fire once, repeat every 4h while firing, and send a
# "resolved" note. A dead blocklist URL MUST page here — that duty was created by
# the 2026-07-03 strategy=fast reversal (ledger blocky.md).

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.alerting;

  rulesFile = pkgs.writeText "vmalert-rules.yml" ''
    groups:
      - name: fleet
        interval: 30s
        rules:
          - alert: InstanceDown
            expr: up == 0
            for: 5m
            labels: { severity: critical }
            annotations:
              summary: "{{ $labels.host }} scrape target down ({{ $labels.job }}/{{ $labels.instance }})"

          - alert: DiskAlmostFull
            expr: >-
              (node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay"}
               / node_filesystem_size_bytes) < 0.15
            for: 15m
            labels: { severity: warning }
            annotations:
              summary: "{{ $labels.host }} {{ $labels.mountpoint }} under 15% free"

          - alert: MemoryPressure
            expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.10
            for: 10m
            labels: { severity: warning }
            annotations:
              summary: "{{ $labels.host }} under 10% memory available (dns1-OOM class)"

      - name: blocky
        interval: 30s
        rules:
          # The strategy=fast contract: list failures no longer take DNS down,
          # so they MUST page instead. refreshPeriod is 4h; >6h stale = missed one.
          - alert: BlockyListRefreshStale
            expr: (time() - blocky_last_list_group_refresh_timestamp_seconds) > 21600
            for: 30m
            labels: { severity: warning }
            annotations:
              summary: "{{ $labels.host }} blocklist group '{{ $labels.group }}' not refreshed in 6h+ (dead URL? see ledger blocky.md NRD incident)"

          - alert: BlockyFailedDownloads
            expr: increase(blocky_failed_downloads_total[1h]) > 3
            labels: { severity: warning }
            annotations:
              summary: "{{ $labels.host }} blocklist downloads failing repeatedly this hour"
  '';

  bridge = pkgs.writeText "am-ntfy-bridge.py" ''
    """Alertmanager webhook -> ntfy (LAN). Loopback-only, stdlib-only."""
    import json, urllib.request
    from http.server import BaseHTTPRequestHandler, HTTPServer

    NTFY = "${cfg.ntfyUrl}"
    TOPIC_FILE = "${config.age.secrets.ntfy-alert-topic.path}"

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            try:
                data = json.loads(body)
                topic = open(TOPIC_FILE).read().strip()
                for a in data.get("alerts", []):
                    firing = a.get("status") == "firing"
                    name = a.get("labels", {}).get("alertname", "alert")
                    sev = a.get("labels", {}).get("severity", "warning")
                    summary = a.get("annotations", {}).get("summary", name)
                    title = ("🔥 " if firing else "✅ resolved: ") + name
                    prio = "high" if (firing and sev == "critical") else ("default" if firing else "min")
                    req = urllib.request.Request(
                        f"{NTFY}/{topic}", data=summary.encode(),
                        headers={"Title": title.encode("utf-8").decode("latin-1"),
                                 "Priority": prio, "Tags": "chart_with_downwards_trend"})
                    urllib.request.urlopen(req, timeout=10)
                self.send_response(200)
            except Exception as e:
                print(f"bridge error: {e}", flush=True)
                self.send_response(500)
            self.end_headers()

        def log_message(self, *args):  # journald gets errors only
            pass

    HTTPServer(("127.0.0.1", ${toString cfg.bridgePort}), H).serve_forever()
  '';
in
{
  options.mySystem.alerting = {
    enable = lib.mkEnableOption "the alerting spine (vmalert + Alertmanager + ntfy bridge)";

    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://192.168.20.10";
      description = "ntfy server, LAN address — deliberately never the tailnet URL.";
    };
    bridgePort = lib.mkOption {
      type = lib.types.port;
      default = 9099;
      description = "Loopback port for the Alertmanager→ntfy webhook bridge.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.ntfy-alert-topic = {
      file = ../../secrets/ntfy-alert-topic.age;
      mode = "0444";  # topic-obscurity secret; observ is single-purpose, root+DynamicUsers read it
    };

    services.vmalert = {
      enable = true;
      settings = {
        "datasource.url" = "http://127.0.0.1:8428";
        "notifier.url" = [ "http://127.0.0.1:9093" ];
        "rule" = [ "${rulesFile}" ];
        "httpListenAddr" = "127.0.0.1:8880";
      };
    };

    services.prometheus.alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9093;
      configuration = {
        route = {
          receiver = "ntfy";
          group_by = [ "alertname" ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
        };
        receivers = [{
          name = "ntfy";
          webhook_configs = [{
            url = "http://127.0.0.1:${toString cfg.bridgePort}/alert";
            send_resolved = true;
          }];
        }];
      };
    };

    systemd.services.am-ntfy-bridge = {
      description = "Alertmanager -> ntfy LAN bridge";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${bridge}";
        Restart = "always";
        DynamicUser = true;
      };
    };
  };
}
