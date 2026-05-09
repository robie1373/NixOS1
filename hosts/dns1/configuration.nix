# hosts/dns1/configuration.nix
#
# Primary DNS resolver — replaces technitium1 (VMID 102, pve).
# VMID: TBD  |  IP: 192.168.20.53/24  |  Node: pve  |  VLAN: 20
#
# Runs Blocky: recursive resolver + hagezi pro/nrd7 + StevenBlack fakenews blocking.
# Stateless — no persistent data. Safe to destroy and redeploy at any time.
#
# After provisioning:
#   1. Tailscale joins automatically on first boot (tailscale-autoconnect.nix).
#   2. Verify DNS from any client: host google.com 192.168.20.53
#   3. Verify blocking: host doubleclick.net 192.168.20.53 (should return NXDOMAIN)
#   4. Update fw DHCP option 6 and Tailscale global nameservers once all three
#      DNS instances are confirmed healthy.

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

  # ── Identity ─────────────────────────────────────────────────────────────
  networking.hostName = "dns1";

  # ── Network ──────────────────────────────────────────────────────────────
  networking.interfaces.ens18.ipv4.addresses = [{
    address      = "192.168.20.53";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";

  # Bootstrap: use fw/public DNS until this instance is fully deployed.
  # Once all three DNS instances pass health checks, these can point at
  # 192.168.20.53/54/55 for self-resolution (take care to avoid loops).
  networking.nameservers = [ "192.168.20.254" "1.1.1.1" ];

  # ── SSH ───────────────────────────────────────────────────────────────────
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── DNS service ───────────────────────────────────────────────────────────
  mySystem.blocky = {
    enable = true;
    localDns = {
      # Hypervisors
      "pve.home.lab"  = "192.168.7.40";
      "pve2.home.lab" = "192.168.7.159";
      # NixOS lab services (VLAN 20)
      "ntfy.home.lab"    = "192.168.20.10";
      "langlab.home.lab" = "192.168.20.11";
      "omada.home.lab"   = "192.168.20.50";
      "dns1.home.lab"    = "192.168.20.53";
      "dns2.home.lab"    = "192.168.20.54";
      "dns3.home.lab"    = "192.168.20.55";
      "nixsrv1.home.lab" = "192.168.20.55";
      # NAS
      "nas.home.lab"     = "192.168.20.12";
      # Legacy Ubuntu services (VLAN 10 — update IPs as services migrate to VLAN 20)
      "karakeep.home.lab" = "192.168.7.57";
      "director.home.lab" = "192.168.7.58";
      "nginx.home.lab"    = "192.168.7.59";
      "habla.home.lab"    = "192.168.7.55";
    };
  };

  system.stateVersion = "25.05";
}
