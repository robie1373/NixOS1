# hosts/vhost1/guests/ntfy.nix
#
# ntfy — push-notification server, as a microVM guest of vhost1 (rung 5 —
# replaces the ntfy Proxmox VM 109 at the same IP .20.10; authored 2026-07-16,
# Fable 5, as rung-5 prep).
#
# URL DECIDED (Robie, 2026-07-16): phone already re-subscribed to the LAN URL
# (http://ntfy.home.lab — the plain-HTTP vhost the module has served since
# 2026-07-03). "Tailscale is dead." → mySystem.ntfy.tls = false drops the
# TS-cert vhost + cert service; base-url becomes http://ntfy.home.lab.

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

    shares = [
      {
        source     = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag        = "ro-store";
        proto      = "virtiofs";
      }
      # Host-staged secrets, read-only (guests hold no agenix): the admin
      # password arrives from the host — see ../configuration.nix stage service.
      {
        source     = "/var/lib/guest-secrets/ntfy";
        mountPoint = "/run/host-secrets";
        tag        = "host-secrets";
        proto      = "virtiofs";
      }
    ];

    # ── Licensed volume: CLASS 2 — ntfy cache + config-recreated user.db.
    # **LICENSED by Robie 2026-07-16** (weekly wipe; register in class2Volumes
    # when phase2 enables). Loss story (law 7): 24h cache — AM re-pages anything
    # still firing; user.db recreated from config. NEVER restic.
    #
    # ⚠️ MOUNT AT /var/lib/private/ntfy-sh, NOT /var/lib/ntfy-sh (fix 2026-07-17,
    # Opus 4.8). ntfy-sh runs DynamicUser=yes + StateDirectory=ntfy-sh: systemd
    # keeps the real state in /var/lib/private/ntfy-sh and puts only a SYMLINK at
    # /var/lib/ntfy-sh. A volume mounted at the symlink target collides →
    # "Failed to set up special execution directory: Device or resource busy".
    # Mounting at the private path IS the state dir, so the narrow single-dataset
    # mount (law 8) and DynamicUser hardening both hold. systemd mkdir -p's the
    # mountpoint and enforces /var/lib/private mode 0700 at service start.
    volumes = [{
      image      = "ntfy-cache.img";
      mountPoint = "/var/lib/private/ntfy-sh";
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
  networking.nameservers = [ "192.168.20.254" ];   # gateway-only (Robie policy 2026-07-21); no 1.1.1.1
  services.resolved.enable = false;

  mySystem.ntfy = {
    enable = true;
    hostname = "ntfy.home.lab";   # LAN-only (see header); phone already re-subscribed
    tls = false;
  };
  # Admin password from the host-staged share, NOT in-guest agenix.
  age.secrets.ntfy-admin-password.path = lib.mkForce "/run/host-secrets/ntfy-admin-password";
  # NOTE: the VM's restic set (tank/backups/services/ntfy) is deliberately NOT
  # carried over — class-2 state is never restic'd (law 8). History stays on NAS.

  # ── microVM boot overrides (see vhost2 guests) ────────────────────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;
  system.configurationRevision = lib.mkForce null;   # per-guest restart granularity

  system.stateVersion = "25.05";
}
