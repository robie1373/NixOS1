# hosts/langlab/configuration.nix
#
# LangLab language learning suite.
# VMID: 111  |  IP: 192.168.20.11/24  |  Node: pve  |  VLAN: 20
#
# Access: https://langlab.vimba-stairs.ts.net (Tailscale only)
#
# After provisioning:
#   1. Tailscale joins automatically on first boot (tailscale-autoconnect.nix).
#   2. tailscale-cert.service provisions TLS on each boot automatically.
#   3. Import Korean vocab: python3 scripts/import_apkg.py <deck.apkg> --user robie --language korean
#   4. Access: https://langlab.vimba-stairs.ts.net

{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/langlab.nix
    ../../modules/_system/tailscale-autoconnect.nix
    ../../modules/_features/tailscale-watchdog.nix
    ../../modules/_features/restic.nix
  ];

  # ── Identity ─────────────────────────────────────────────────────────────
  networking.hostName = "langlab";

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
    hostname = "langlab.vimba-stairs.ts.net";
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
