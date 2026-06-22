# hosts/pages/configuration.nix
#
# pages — static web host.
# VMID: 115  |  IP: 192.168.20.57/24  |  Node: pve2  |  VLAN: 20
# Suggested Proxmox spec: 1 vCPU, 512 MB RAM, 16 GB virtio disk, UEFI.
#
# Placed on pve2 (not pve) per the capacity check in the provisioning runbook:
# pve runs hot (~3.6 GiB free), pve2 had ~8.5 GiB free at provisioning time.
#
# Serves self-contained HTML from ./www over plain HTTP on the LAN.
# Reachable at http://192.168.20.57. Losing this host loses static pages, not
# services — safe to redeploy; content is reproduced from the repo.

{ inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/pages.nix
    ../../modules/_system/tailscale-autoconnect.nix
    ../../modules/_features/tailscale-watchdog.nix
  ];

  # ── Identity ───────────────────────────────────────────────────────────────
  networking.hostName = "pages";

  # ── Network ────────────────────────────────────────────────────────────────
  networking.interfaces.ens18.ipv4.addresses = [{
    address      = "192.168.20.57";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";
  # External DNS by choice. pages serves static files and resolves nothing
  # internal, so it uses Cloudflare directly rather than depending on dns1 being
  # up (same rationale as observ). Hosts needing .home.lab names point at dns1.
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

  # ── Static site ────────────────────────────────────────────────────────────
  mySystem.pages.enable = true;
  mySystem.pages.contentRoot = ./www;

  system.stateVersion = "25.05";
}
