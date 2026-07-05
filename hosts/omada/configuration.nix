# hosts/omada/configuration.nix
#
# TP-Link Omada SDN controller — manages EAP773 APs and SG3210XHP-M2 switch.
# VMID: 110  |  IP: 192.168.20.50/24  |  Node: pve  |  VLAN: 20
#
# Web UI: https://192.168.20.50:8843 (self-signed cert; accept the browser warning)
#         Once Tailscale is up: https://<tailscale-ip>:8843
#
# After provisioning:
#   1. Tailscale joins automatically on first boot (tailscale-autoconnect.nix).
#   2. Access web UI at https://192.168.20.50:8843 — complete setup wizard.
#   3. In Site Settings → Controller → inform URL: http://192.168.20.50:8043
#      (APs use this to find the controller on the LAN)

{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/omada-controller.nix
    ../../modules/_system/tailscale-autoconnect.nix
    ../../modules/_features/tailscale-watchdog.nix
    ../../modules/_features/restic.nix
  ];

  # ── Identity ──────────────────────────────────────────────────────────────
  networking.hostName = "omada";

  # ── Network ───────────────────────────────────────────────────────────────
  # Static IP on VLAN 20 (lab infrastructure subnet).
  # This IP must not change — APs are configured to reach the controller here.
  networking.interfaces.ens18.ipv4.addresses = [{
    address = "192.168.20.50";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";  # OPNsense lab gateway

  # Override /etc/hosts so the LAN IP is the ONLY resolution for "omada".
  # Problem: NixOS auto-generates "127.0.0.2 omada" (from networking.hostName)
  # BEFORE any networking.hosts entries, so Java resolves "omada" → 127.0.0.2
  # and advertises that loopback address in adoption inform URLs — unreachable
  # by switches and APs on the network.
  # Fix: mkForce the entire hosts file, putting 192.168.20.50 first and
  # omitting the 127.0.0.2 entry (not needed for controller operation).
  environment.etc."hosts".text = lib.mkForce ''
    127.0.0.1 localhost
    ::1 localhost
    192.168.20.50 omada
  '';

  # DNS: OPNsense gateway primary, public fallback. Technitium is on VLAN 10
  # and unreachable from VLAN 20 until inter-VLAN routing is fixed. Using
  # 192.168.20.254 (OPNsense) as primary — it resolves external names and is
  # always reachable on VLAN 20. Update when Technitium moves to VLAN 20.
  networking.nameservers = [ "192.168.20.254" "1.1.1.1" ];

  # ── SSH authorised keys ───────────────────────────────────────────────────
  # ansible2 key is set in server-common. Personal key added for interactive use.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── Omada controller ──────────────────────────────────────────────────────
  mySystem.omada-controller.enable = true;

  # ── Restic backups ────────────────────────────────────────────────────────
  # Back up only the MongoDB data directory. logs/ and work/ are transient.
  # Note: Omada controller runs MongoDB live during backup — restore may require
  # stopping the container and doing a clean restore. See backup runbook.
  mySystem.restic.backups.omada = {
    nasPath = "tank/backups/services/omada";
    paths   = [ "/var/lib/omada-controller/data" ];
  };

  # ── State version ─────────────────────────────────────────────────────────
  system.stateVersion = "25.05";
}
