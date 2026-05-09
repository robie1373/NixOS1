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
#   [x] NIC confirmed: enp0s20u1 (USB-C Ethernet adapter, 2026-05-09)
#   [x] Disk confirmed: /dev/sda 699.7GB SATA SSD (2026-05-09)
#   [x] Copy personal key to root (ansible2 key copied 2026-05-09, root SSH confirmed)
#   [x] Run `ssh root@192.168.7.126 nixos-generate-config --show-hardware-config` → hardware-configuration.nix saved
#   [x] Generate host SSH key: generated 2026-05-09
#       → private key stored in 1Password devops/"nixsrv1 host SSH key"
#       → public key committed to hosts/nixsrv1/ssh_host_ed25519_key.pub
#       → added to secrets/secrets.nix recipients (re-key pending: nix run github:ryantm/agenix -- -r)
#   [ ] Configure SG108PE port 7: PVID=20, member of VLAN 20 untagged
#   [ ] Add microvm flake input to flake.nix (see modules/hosts/nixsrv1/default.nix)

{ inputs, config, lib, ... }:

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
  # USB-C Ethernet adapter — confirmed enp0s20u1 via `ip link show` 2026-05-09.
  # altname: enxe000000fab75 (MAC-based). Use enp0s20u1.
  networking.interfaces.enp0s20u1.ipv4.addresses = [{
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
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  system.stateVersion = "25.05";
}
