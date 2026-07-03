# hosts/dns2/configuration.nix
#
# Secondary DNS resolver — replaces technitium2 (VMID 101, pve2) under
# all-nixos-lab Project A. VMID: 113  |  IP: 192.168.20.54/24  |  Node: pve2  |  VLAN: 20
#
# Identical Blocky config to dns1 (shared localDns map lives in the blocky
# module — single source of truth). Blocky is stateless, no replication needed.
# Runs on pve2 for redundancy across hypervisors; dns1 (pve) is the pair.
#
# No Tailscale: provisioned 2026-07-03, mid-decommission — new hosts don't
# join the tailnet. (dns1 predates this and still carries the modules; its
# cleanup belongs to the fleet-wide Tailscale decommission task.)
#
# After provisioning:
#   1. Verify DNS: dig @192.168.20.54 google.com
#   2. Verify blocking: dig @192.168.20.54 doubleclick.net  (expect 0.0.0.0)
#   3. Verify query logs land in VictoriaLogs (host:dns2)
#   4. Reboot test (chaos-monkey) before declaring healthy.

{ inputs, config, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/blocky.nix
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

  mySystem.blocky.enable = true;

  system.stateVersion = "25.05";
}
