# hosts/vhost1/guests/langlab.nix
#
# langlab — language-learning suite, as a microVM guest of vhost1 (rung 5 —
# replaces Proxmox VM 111 at the same IP .20.11; authored 2026-07-16, Fable 5,
# as rung-5 prep).
#
# Secrets (doctrine: guests hold NO agenix — host keys churn): the API keys
# arrive via a read-only virtiofs share from the HOST, which decrypts
# langlab-env (re-encrypted to vhost1 at the key ceremony) and stages it under
# /var/lib/guest-secrets/langlab/. See the stage service in ../configuration.nix.

{ inputs, config, lib, pkgs, ... }:

let
  mac = "02:00:00:00:20:11";   # mnemonic: VLAN 20, host octet 11
in
{
  imports = [
    ../../../modules/_system/server-common.nix
    ../../../modules/_system/langlab.nix
  ];

  networking.hostName = "langlab";

  microvm = {
    hypervisor = "qemu";
    vcpu = 1;
    mem  = 1536;

    shares = [
      {
        source     = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag        = "ro-store";
        proto      = "virtiofs";
      }
      # Host-staged secrets, read-only (see header). Guest sees the decrypted
      # env file at /run/host-secrets/langlab-env.
      {
        source     = "/var/lib/guest-secrets/langlab";
        mountPoint = "/run/host-secrets";
        tag        = "host-secrets";
        proto      = "virtiofs";
      }
    ];

    # ── Licensed volume: CLASS 4 — study.db (SQLite, user study history) +
    # languages/ audio, exactly /var/lib/langlab. User-created content →
    # class 4 (Robie's ruling class applies; confirm at rung-5 review).
    # Loss story (law 7): vhost1 restic set `langlab` (same NAS repo as the VM
    # era → history preserved); audio re-importable from ~/languages sources.
    # NEVER in class2Volumes.
    volumes = [{
      image      = "langlab-var.img";
      mountPoint = "/var/lib/langlab";
      size       = 8192;              # 8 GiB (study.db + lesson audio clips)
      fsType     = "ext4";
      autoCreate = true;
    }];

    interfaces = [{ type = "tap"; id = "vm-langlab"; inherit mac; }];
  };

  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = mac;
    address = [ "192.168.20.11/24" ];
    routes  = [ { Gateway = "192.168.20.254"; } ];
  };
  networking.nameservers = [ "192.168.20.254" "1.1.1.1" ];
  services.resolved.enable = false;

  mySystem.langlab = {
    enable   = true;
    hostname = "langlab.home.lab";
  };
  # API keys from the host-staged share, NOT in-guest agenix (see header).
  systemd.services.langlab.serviceConfig.EnvironmentFile =
    lib.mkForce "/run/host-secrets/langlab-env";

  # ── microVM boot overrides (see vhost2 guests) ────────────────────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  system.configurationRevision = lib.mkForce null;

  system.stateVersion = "25.05";
}
