# hosts/dns2/configuration.nix
#
# Secondary DNS resolver — replaces technitium2 (VMID 101, pve2).
# VMID: TBD  |  IP: 192.168.20.54/24  |  Node: pve2  |  VLAN: 20
#
# Identical config to dns1 — Blocky is stateless, no replication needed.
# Runs on pve2 for redundancy across hypervisors.
#
# After provisioning:
#   1. Tailscale joins automatically on first boot.
#   2. Verify: host google.com 192.168.20.54
#   3. Verify blocking: host doubleclick.net 192.168.20.54

{ inputs, config, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/blocky.nix
    ../../modules/_system/tailscale-autoconnect.nix
    ../../modules/_features/tailscale-watchdog.nix
  ];

  networking.hostName = "dns2";

  networking.interfaces.ens18.ipv4.addresses = [{
    address      = "192.168.20.54";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";
  networking.nameservers    = [ "192.168.20.254" "1.1.1.1" ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  mySystem.blocky = {
    enable = true;
    localDns = {
      "pve.home.lab"  = "192.168.7.40";
      "pve2.home.lab" = "192.168.7.159";
      "ntfy.home.lab"    = "192.168.20.10";
      "langlab.home.lab" = "192.168.20.11";
      "omada.home.lab"   = "192.168.20.50";
      "dns1.home.lab"    = "192.168.20.53";
      "dns2.home.lab"    = "192.168.20.54";
      "dns3.home.lab"    = "192.168.20.55";
      "nixsrv1.home.lab" = "192.168.20.55";
      "nas.home.lab"     = "192.168.20.12";
      "karakeep.home.lab" = "192.168.7.57";
      "director.home.lab" = "192.168.7.58";
      "nginx.home.lab"    = "192.168.7.59";
      "habla.home.lab"    = "192.168.7.55";
    };
  };

  system.stateVersion = "25.05";
}
