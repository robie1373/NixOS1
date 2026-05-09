# hosts/nixsrv1/configuration.nix
#
# nixsrv1 — Intel MacBook Pro, bare metal NixOS.
# IP: 192.168.20.55/24  |  VLAN: 20  |  Switch: SG108PE port 7
#
# Dual role:
#   1. dns3 — third Blocky DNS instance (redundancy across pve, pve2, bare metal)
#   2. Hypervisor — KVM/libvirt, Podman, microvm.nix for future Proxmox replacement
#
# PRE-DEPLOY CHECKLIST:
#   [ ] Copy ansible2 key to machine (ssh-copy-id with echo of known pubkey)
#   [ ] Run `ip link show` to get actual NIC interface name — update networking.interfaces below
#   [ ] Run `lsblk` to confirm /dev/nvme0n1 is correct — update disko.nix if not
#   [ ] Run `nixos-generate-config --show-hardware-config` → save as hardware-configuration.nix
#   [ ] Generate host SSH key: ssh-keygen -t ed25519 -f /tmp/nixsrv1_host_key -N ""
#       → store private key in 1Password devops/"nixsrv1 host SSH key"
#       → commit public key to hosts/nixsrv1/ssh_host_ed25519_key.pub
#       → add to secrets/secrets.nix recipients, re-key: nix run github:ryantm/agenix -- -r
#   [ ] Configure SG108PE port 7: PVID=20, member of VLAN 20 untagged
#   [ ] Add microvm flake input to flake.nix (see modules/hosts/nixsrv1/default.nix)

{ inputs, config, ... }:

{
  imports = [
    ./hardware-configuration.nix   # TODO: generate with nixos-generate-config
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/blocky.nix
    ../../modules/_system/hypervisor.nix
    ../../modules/_system/tailscale-autoconnect.nix
    ../../modules/_features/tailscale-watchdog.nix
  ];

  # ── Identity ──────────────────────────────────────────────────────────────
  networking.hostName = "nixsrv1";

  # ── Network ───────────────────────────────────────────────────────────────
  # TODO: Run `ip link show` on the machine before deploying to confirm
  # the Ethernet adapter interface name. Intel MBP uses USB-C/Thunderbolt
  # adapters — NIC names vary by adapter: enp0s20f0u1, enp2s0, eth0, etc.
  # Replace TODO_NIC_NAME below with the actual name.
  networking.interfaces.TODO_NIC_NAME.ipv4.addresses = [{
    address      = "192.168.20.55";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";
  networking.nameservers    = [ "192.168.20.254" "1.1.1.1" ];

  # ── SSH ───────────────────────────────────────────────────────────────────
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── DNS service (dns3 role) ───────────────────────────────────────────────
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

  # ── Hypervisor ────────────────────────────────────────────────────────────
  mySystem.hypervisor.enable = true;

  # ── Apple hardware quirks ─────────────────────────────────────────────────
  # Intel MBP uses Apple EFI — systemd-boot works but some firmware vars
  # may be read-only. canTouchEfiVariables is set to false as a precaution.
  # server-common.nix sets it true; override here.
  boot.loader.efi.canTouchEfiVariables = false;

  system.stateVersion = "25.05";
}
