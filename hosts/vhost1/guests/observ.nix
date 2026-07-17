# hosts/vhost1/guests/observ.nix
#
# observ — visibility stack (VictoriaMetrics + VictoriaLogs + Grafana +
# vmalert/Alertmanager), as a microVM guest of vhost1 (rung 5 — replaces
# Proxmox VM 114 at the same IP .20.56; authored 2026-07-16, Fable 5, prep).
#
# ⚠️ Sequencing ([[vhost1-conversion]]): convert observ EARLY in the window and
# verify scrapes resume before converting the rest — it is the eyes for the
# remaining migrations. During its own migration, downness detection = direct
# host interrogation (Robie's ruling 2026-07-16: that route still exists).
#
# Secrets (guests hold NO agenix): observability/alerting consume four secrets
# (ntfy-alert-topic, snmp-config, pve-exporter-token, grafana-admin-pass).
# They arrive via the host-staged read-only share (see ../configuration.nix);
# the path overrides below point every consumer at the share. pve-exporter is
# MOOT at rung 5 (pve dies) — keep it disabled.

{ inputs, config, lib, pkgs, ... }:

let
  mac = "02:00:00:00:20:56";   # mnemonic: VLAN 20, host octet 56
in
{
  imports = [
    ../../../modules/_system/server-common.nix
    ../../../modules/_system/observability.nix
    ../../../modules/_system/alerting.nix
  ];

  networking.hostName = "observ";

  microvm = {
    hypervisor = "qemu";
    vcpu = 2;
    mem  = 4096;

    shares = [
      {
        source     = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag        = "ro-store";
        proto      = "virtiofs";
      }
      {
        source     = "/var/lib/guest-secrets/observ";
        mountPoint = "/run/host-secrets";
        tag        = "host-secrets";
        proto      = "virtiofs";
      }
    ];

    # ── Licensed volumes: CLASS 2 — the trailing metrics/logs windows, split
    # narrow per the pre-classification in [[new-service-protocol]].
    # **LICENSED by Robie 2026-07-16.** Loss story (law 7): the 10-day troubleshooting window
    # is priced in as losable; dashboards/alerts are code and rebuild.
    # ⚠️ Wipe cadence must be MONTHLY, not weekly — the data IS the trailing
    # window. The phase-2 monthly-exception mechanism does NOT exist yet, so
    # these are NOT registered in class2Volumes; wipe manually on a monthly
    # patch day until the exception lands. Grafana state stays ephemeral.
    #
    # ⚠️ MOUNT AT /var/lib/private/<name>, NOT /var/lib/<name> (fix 2026-07-17,
    # Opus 4.8). Both services run DynamicUser=yes + StateDirectory: real state
    # lives in /var/lib/private/<name>, only a symlink at /var/lib/<name>. A
    # volume at the symlink target → "Device or resource busy" (start-limit loop).
    # See guests/ntfy.nix for the full rationale.
    volumes = [
      { image = "observ-vm.img"; mountPoint = "/var/lib/private/victoriametrics";
        size = 8192; fsType = "ext4"; autoCreate = true; }
      { image = "observ-vl.img"; mountPoint = "/var/lib/private/victorialogs";
        size = 8192; fsType = "ext4"; autoCreate = true; }
    ];

    interfaces = [{ type = "tap"; id = "vm-observ"; inherit mac; }];
  };

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = mac;
    address = [ "192.168.20.56/24" ];
    routes  = [ { Gateway = "192.168.20.254"; } ];
  };
  networking.nameservers = [ "192.168.20.254" "1.1.1.1" ];
  services.resolved.enable = false;

  mySystem.observability.enable = true;
  mySystem.alerting.enable = true;
  # pve-exporter stays off: its target dies at this very rung.

  # Re-point every agenix consumer at the host-staged share (the .age files
  # still exist in secrets/ so evaluation succeeds; runtime decryption happens
  # on the HOST, not here). agenix's own decrypt units are inert failures for
  # these — acceptable; the share is the delivery path.
  age.secrets.ntfy-alert-topic.path   = lib.mkForce "/run/host-secrets/ntfy-alert-topic";
  age.secrets.snmp-config.path        = lib.mkForce "/run/host-secrets/snmp-config";
  age.secrets.grafana-admin-pass.path = lib.mkForce "/run/host-secrets/grafana-admin-pass";

  # ── microVM boot overrides (see vhost2 guests) ────────────────────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  system.configurationRevision = lib.mkForce null;

  system.stateVersion = "25.05";
}
