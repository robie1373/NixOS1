# hosts/vhost1/guests/ntfy.nix
#
# ntfy — push-notification server, as a microVM guest of vhost1 (rung 5 —
# replaces the ntfy Proxmox VM 109 at the same IP .20.10; authored 2026-07-16,
# Fable 5, as rung-5 prep).
#
# ⚠️ EXECUTION-DAY DECISION (Robie): mySystem.ntfy.hostname is the Tailscale
# name (vimba-stairs cert) and the PHONE APP subscribes to that URL. Tailscale
# is off in guests (and being decommissioned fleet-wide) — the cert acquisition
# path dies with the VM. Options: serve plain HTTP on LAN (pages precedent) and
# re-point the phone subscription, or a home.lab cert story. Decide BEFORE
# migrating; the phone alert path is production-enabling ([[ntfy]]).

{ inputs, config, lib, pkgs, ... }:

let
  mac = "02:00:00:00:20:10";   # mnemonic: VLAN 20, host octet 10
in
{
  imports = [
    ../../../modules/_system/server-common.nix
    ../../../modules/_system/ntfy.nix
  ];

  networking.hostName = "ntfy";

  microvm = {
    hypervisor = "qemu";
    vcpu = 1;
    mem  = 1024;

    shares = [{
      source     = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag        = "ro-store";
      proto      = "virtiofs";
    }];

    # ── Licensed volume: CLASS 2 — ntfy cache + config-recreated user.db,
    # exactly /var/lib/ntfy-sh (pre-classified in [[new-service-protocol]];
    # license it at the rung-5 review). Loss story (law 7): 24h message cache —
    # AM re-pages anything still firing; user.db recreated from config.
    # Class 2 ⇒ REGISTER in vhost1 patchAutomation.phase2.class2Volumes
    # (weekly wipe fine per the pre-classification) and NEVER restic.
    volumes = [{
      image      = "ntfy-cache.img";
      mountPoint = "/var/lib/ntfy-sh";
      size       = 1024;              # 1 GiB
      fsType     = "ext4";
      autoCreate = true;              # load-bearing: how class-2 wipe-rehydrate works
    }];

    interfaces = [{ type = "tap"; id = "vm-ntfy"; inherit mac; }];
  };

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = mac;
    address = [ "192.168.20.10/24" ];
    routes  = [ { Gateway = "192.168.20.254"; } ];
  };
  networking.nameservers = [ "192.168.20.254" "1.1.1.1" ];
  services.resolved.enable = false;

  mySystem.ntfy = {
    enable = true;
    hostname = "ntfy.vimba-stairs.ts.net";   # see EXECUTION-DAY DECISION above
  };
  # NOTE: the VM's restic set (tank/backups/services/ntfy) is deliberately NOT
  # carried over — class-2 state is never restic'd (law 8). History stays on NAS.

  # ── microVM boot overrides (see vhost2 guests) ────────────────────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  system.configurationRevision = lib.mkForce null;   # per-guest restart granularity

  system.stateVersion = "25.05";
}
