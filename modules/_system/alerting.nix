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

      - name: wan
        interval: 30s
        rules:
          # Added 2026-08-17 after an edge outage that observ slept through entirely.
          # THREE rules, not one, because the three failure shapes need different
          # reactions and a single rule would blur them.

          # 1. Everything external is unreachable => it is the edge, not a provider.
          #    sum()==0 means no target succeeded. This is the one that means "call
          #    Verizon" / "power-cycle the box".
          - alert: WanDown
            expr: sum(probe_success{job="blackbox-wan-dns"}) == 0
            for: 2m
            labels: { severity: critical }
            annotations:
              summary: "WAN DOWN — no external resolver answering (all probe targets failed). Lab DNS for home.lab is unaffected; anything off-LAN is not."

          # 2. One provider down while the other answers => that provider's problem.
          #    Deliberately NOT critical: this is the case a single-target probe would
          #    have mistaken for an outage, which is how alerts lose credibility.
          - alert: WanResolverDegraded
            expr: probe_success{job="blackbox-wan-dns"} == 0
            for: 5m
            labels: { severity: warning }
            annotations:
              summary: "{{ $labels.instance }} not answering, but another external resolver still is — provider-specific, not the edge."

          # 3. The metric vanished. A probe that stopped being scraped produces NO
          #    series, so rules 1 and 2 both go quiet and silence reads exactly like
          #    a healthy WAN. absent() is the only thing that catches a dead monitor.
          - alert: WanProbeMissing
            expr: absent(probe_success{job="blackbox-wan-dns"})
            for: 10m
            labels: { severity: warning }
            annotations:
              summary: "WAN DNS probe is reporting NO data — blackbox_exporter or its scrape job is broken. WAN state is UNKNOWN, not healthy."

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

  # LogsQL alerting rules — evaluated by the SECOND vmalert instance below
  # (vmalert serves exactly one datasource; this one points at VictoriaLogs).
  vlogsRulesFile = pkgs.writeText "vmalert-vlogs-rules.yml" ''
    groups:
      - name: spine-probe
        type: vlogs
        interval: 1m
        rules:
          # The Wednesday positive probe (Robie, 2026-07-04): a timer digs a
          # unique subdomain of a blocked wildcard through the fw; Blocky blocks
          # + query-logs it; this rule sees the log line and pages 🟢. One green
          # ping every Wednesday proves dig→fw→blocky→journald→Alloy→VL→vmalert→
          # AM→bridge→ntfy→phone end-to-end. Contract: NO green ping on a
          # Wednesday morning = the spine is broken somewhere — investigate.
          - alert: SpineWeeklyProbe
            expr: '"queryLog" "spine-probe" "response_type=BLOCKED" | stats count() as hits | filter hits:>0'
            labels: { severity: info }
            annotations:
              summary: "Wednesday spine probe blocked+logged+alerted end-to-end — all green ({{$value}} hit)"

      - name: ids
        type: vlogs
        interval: 1m
        rules:
          # fw suricata EVE alerts flow to VL via syslog (app_name=suricata,
          # see visibility-stack.md). Zero events is the norm, so ANY event
          # pages. Rudimentary by design — tune when the ruleset grows.
          - alert: SuricataIDSEvent
            expr: 'app_name:="suricata" | stats count() as events | filter events:>0'
            labels: { severity: critical }
            annotations:
              summary: "fw IDS: suricata event(s) in the last minute — check VL app_name:=suricata ({{$value}} lines)"
  '';

  # Wednesday spine probe: dig the owned canary domain (spine-probe.canary —
  # inline denylist entry in blocky.nix; always blocked exactly, never in real
  # traffic; blocked answers are logged on every query so no uniqueness games)
  # at BOTH resolvers. The vlogs rule above turns the BLOCKED query-log lines
  # into the green ping. Digs dns1/dns2 directly, NOT via fw dnsmasq: VLAN 20 →
  # fw:53 times out fleet-wide (finding 2026-07-04, see ledger fw.md), and the
  # fw hop is continuously proven by live household traffic anyway — this
  # probe's job is the blocky→log→alert→phone pipeline.
  # Learned the hard way (2026-07-04): blocky does NOT block subdomains of
  # plain list entries — the first canary (unique *.doubleclick.net names) was
  # forwarded upstream, never blocked.
  spineProbe = pkgs.writeShellScript "spine-probe" ''
    set -u
    for ns in 192.168.20.53 192.168.20.54; do
      domain="spine-probe.canary"
      ans=$(${pkgs.dnsutils}/bin/dig +short +time=5 @$ns "$domain" A | head -1)
      echo "spine-probe: $domain @$ns -> ''${ans:-NOANSWER} (0.0.0.0 = blocked, expected)"
    done
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
                    # severity drives emoji + priority; info-class alerts are
                    # positive/heartbeat signals (e.g. the Wednesday spine probe)
                    # and must not look or buzz like a fire.
                    if firing:
                        emoji = {"critical": "🔥", "warning": "⚠️", "info": "🟢"}.get(sev, "⚠️")
                        title = f"{emoji} {name}"
                        prio = {"critical": "high", "warning": "default", "info": "min"}.get(sev, "default")
                    else:
                        title = f"✅ resolved: {name}"
                        prio = "min"
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

    # Second vmalert: LogsQL rules against VictoriaLogs (one instance per
    # datasource — see vlogsRulesFile header). Same Alertmanager downstream.
    systemd.services.vmalert-vlogs = {
      description = "vmalert (VictoriaLogs datasource) — log-based alert rules";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.victoriametrics}/bin/vmalert"
          "-datasource.url=http://127.0.0.1:9428"
          "-notifier.url=http://127.0.0.1:9093"
          "-rule=${vlogsRulesFile}"
          "-httpListenAddr=127.0.0.1:8881"
        ];
        Restart = "always";
        DynamicUser = true;
      };
    };

    systemd.services.spine-probe = {
      description = "Weekly end-to-end spine probe (blocked-domain canary)";
      serviceConfig = { Type = "oneshot"; ExecStart = "${spineProbe}"; };
    };
    systemd.timers.spine-probe = {
      description = "Wednesday spine probe";
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "Wed 09:00"; Persistent = true; };
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
