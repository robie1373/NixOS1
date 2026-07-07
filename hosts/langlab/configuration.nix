# hosts/langlab/configuration.nix
#
# LangLab language learning suite.
# VMID: 111  |  IP: 192.168.20.11/24  |  Node: pve  |  VLAN: 20
#
# Access: http://langlab.home.lab (LAN only — Blocky localDns zone)
#
# Tailscale stripped 2026-07-06 per the 2026-06-22 decommission decision —
# first host cleaned; the mkForce below counters server-common.nix until the
# fleet-wide removal lands there.
#
# After provisioning:
#   Import Korean vocab: python3 scripts/import_apkg.py <deck.apkg> --user robie --language korean

{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/langlab.nix
    ../../modules/_features/restic.nix
  ];

  # ── Identity ─────────────────────────────────────────────────────────────
  networking.hostName = "langlab";

  # ── Tailscale: OFF ────────────────────────────────────────────────────────
  # server-common.nix still enables Tailscale fleet-wide; override until the
  # fleet cleanup removes it there.
  services.tailscale.enable = lib.mkForce false;

  # ── Network ──────────────────────────────────────────────────────────────
  networking.interfaces.ens18.ipv4.addresses = [{
    address      = "192.168.20.11";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";
  # Using public DNS until Technitium is migrated to VLAN 20.
  # When Technitium reaches VLAN 20, replace with internal resolvers.
  networking.nameservers    = [ "1.1.1.1" "1.0.0.1" ];

  # ── SSH authorised keys ───────────────────────────────────────────────────
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── LangLab service ───────────────────────────────────────────────────────
  mySystem.langlab = {
    enable   = true;
    hostname = "langlab.home.lab";
  };

  # ── Restic backups ────────────────────────────────────────────────────────
  # study.db (SQLite) and languages/ audio files. Both are under /var/lib/langlab.
  mySystem.restic.backups.langlab = {
    nasPath = "tank/backups/services/langlab";
    paths   = [ "/var/lib/langlab" ];
  };

  # ── State version ─────────────────────────────────────────────────────────
  system.stateVersion = "25.05";
}
