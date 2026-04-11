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
  ];

  # ── Identity ─────────────────────────────────────────────────────────────
  networking.hostName = "langlab";

  # ── Network ──────────────────────────────────────────────────────────────
  networking.interfaces.ens18.ipv4.addresses = [{
    address      = "192.168.20.11";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";
  networking.nameservers    = [ "192.168.7.53" "192.168.7.54" ];

  # ── SSH authorised keys ───────────────────────────────────────────────────
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── LangLab service ───────────────────────────────────────────────────────
  mySystem.langlab = {
    enable   = true;
    hostname = "langlab.vimba-stairs.ts.net";
  };

  # ── State version ─────────────────────────────────────────────────────────
  system.stateVersion = "25.05";
}
