# hosts/ntfy/configuration.nix
#
# ntfy push notification server — first NixOS lab service.
# VMID: 109  |  IP: 192.168.20.10/24  |  Node: pve  |  VLAN: 20
#
# Tailscale hostname: ntfy.vimba-stairs.ts.net
# Access: https://ntfy.vimba-stairs.ts.net (Tailscale only, no public exposure)
#
# After provisioning:
#   1. SSH in: ssh root@192.168.20.10 (before Tailscale is activated)
#   2. Run: tailscale up --authkey <key from 1Password devops/"Tailscale Auth Key"> \
#             --ssh --hostname=ntfy --advertise-tags=tag:terraformhost
#   3. That's it. `tailscale-cert.service` runs on each boot and provisions
#      the TLS cert to /var/lib/tailscale/certs/ with correct nginx permissions.
#   4. Access: https://ntfy.vimba-stairs.ts.net (once Tailscale is up)

{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/system/server-common.nix
    ../../modules/system/ntfy.nix
  ];

  # ── Identity ─────────────────────────────────────────────────────────────
  networking.hostName = "ntfy";

  # ── Network ──────────────────────────────────────────────────────────────
  # Static IP on VLAN 20 (lab infrastructure subnet).
  # Interface name: ens18 is typical for Proxmox virtio NICs with predictable names.
  # If the actual interface differs after boot, check `ip link` and update here.
  networking.interfaces.ens18.ipv4.addresses = [{
    address = "192.168.20.10";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";  # OPNsense lab gateway

  # DNS: Technitium primary/secondary (current). Update when Blocky is deployed.
  networking.nameservers = [ "192.168.7.53" "192.168.7.54" ];

  # ── SSH authorised keys ───────────────────────────────────────────────────
  # ansible2 key is set in server-common. Add personal key here for interactive use.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── ntfy service ──────────────────────────────────────────────────────────
  mySystem.ntfy = {
    enable = true;
    hostname = "ntfy.vimba-stairs.ts.net";
  };

  # ── State version ─────────────────────────────────────────────────────────
  # Set to the NixOS version active at provisioning time. Never change this
  # after the host is first booted — see docs for rationale.
  # nixos-anywhere installs from the current flake; check `nixos-version` after
  # first boot and confirm this matches.
  system.stateVersion = "25.05";
}
