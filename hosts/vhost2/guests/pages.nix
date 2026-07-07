# hosts/vhost2/guests/pages.nix
#
# pages — static web host, as a microVM guest of vhost2.
# all-nixos-lab rung 4 / Phase B2 step 5. Reprovision-never-migrate (D1): replaces
# the old pages Proxmox VM (VMID 115). Stateless (D10) — the served content is NOT
# in the flake; it is pushed out-of-band from the NAS (~/nas/web/pages/) via
# deploy-pages after the guest is up. So there is no state to restore: build the
# microVM, boot it, re-run deploy-pages.
#
# Passed to the host as `microvm.vms.pages.config`. See ../configuration.nix for
# the guest pattern rationale (mirrors ./dns2.nix).

{ inputs, config, lib, pkgs, ... }:

let
  # Locally-administered MAC. Mnemonic: VLAN 20, host octet 57.
  mac = "02:00:00:00:20:57";
in
{
  imports = [
    ../../../modules/_system/server-common.nix   # ssh, agenix, observability agent, nix pinning
    ../../../modules/_system/pages.nix            # nginx serving /var/www/pages
  ];

  networking.hostName = "pages";

  # ── microVM runtime ──────────────────────────────────────────────────────────
  microvm = {
    hypervisor = "qemu";              # D4
    vcpu = 1;
    mem  = 512;                       # matches the old 512 MB VM

    # D8 — shared read-only host store.
    shares = [{
      source     = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag        = "ro-store";
      proto      = "virtiofs";
    }];

    interfaces = [{
      type = "tap";
      id   = "vm-pages";
      inherit mac;
    }];
  };

  # ── Guest networking: static .20.57 on VLAN 20, matched by MAC ────────────────
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = mac;
    address = [ "192.168.20.57/24" ];
    routes  = [ { Gateway = "192.168.20.254"; } ];
  };
  # External DNS by choice — pages serves static files and resolves nothing
  # internal, so it does not depend on a Blocky guest being up (same as the old VM).
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

  # ── Static site ───────────────────────────────────────────────────────────────
  mySystem.pages.enable = true;
  mySystem.pages.serverNames = [ "pages.home.lab" "192.168.20.57" ];

  # ── microVM boot overrides (see ./dns2.nix) ───────────────────────────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;

  # Guests do NOT embed the nixos-config git rev (server-common sets it from
  # inputs.self.rev). With it, EVERY commit changes every guest closure and a
  # host switch restarts all guests — defeating per-guest restart granularity
  # (proven 2026-07-07). Hosts keep theirs; guests are identity-less anyway.
  system.configurationRevision = lib.mkForce null;

  system.stateVersion = "25.05";
}
