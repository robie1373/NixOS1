# hosts/nixsrv1/configuration.nix
#
# nixsrv1 — Intel MacBook Pro, bare-metal NixOS hypervisor.
# IP: 192.168.20.55/24  |  VLAN: 20 (CoreSwitch Port 1 native/untagged lab(20))
#
# Role: NixOS hypervisor (KVM/libvirt + Podman + microvm.nix). Services run as
# guests, NOT on the host. First guest: a Blocky DNS resolver microVM on VLAN 20
# (replaces the Blocky VM on pve — frees its RAM). The resolver MUST be on VLAN
# 20; it is bridged onto br0 (which carries enp0s20u1) with its own VLAN 20 IP.
#
# Provisioned bare-metal (disko + nixos-install on the running machine), NOT via
# nixos-anywhere kexec — see ledger nixos-service-provisioning "Bare-metal".
#
# Static addressing rule (Robie): all static lab addresses are below .100; the
# DHCP pool is .100–.200. Host = .55; the resolver guest gets another below-.100.

{ inputs, config, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/hypervisor.nix
  ];

  # ── Identity ──────────────────────────────────────────────────────────────
  networking.hostName = "nixsrv1";

  # ── Network ───────────────────────────────────────────────────────────────
  # CoreSwitch Port 1 is native VLAN 20 (untagged), so the USB-C NIC enp0s20u1
  # (confirmed via `ip link`, altname enxe000000fab75) is on VLAN 20. It is
  # enslaved to br0 so microVM guests can be bridged onto VLAN 20 as first-class
  # L2 citizens — the Blocky resolver guest needs its own VLAN 20 address. The
  # host's management IP lives on br0.
  networking.bridges.br0.interfaces = [ "enp0s20u1" ];
  networking.interfaces.br0.ipv4.addresses = [{
    address      = "192.168.20.55";   # static, below .100 (DHCP pool is .100–.200)
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";
  # VLAN 20's DHCP-assigned resolver (.254) does not resolve external names, and
  # the host must not hard-depend on the Blocky guest it runs. Use public DNS.
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

  # ── SSH ───────────────────────────────────────────────────────────────────
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── Hypervisor ────────────────────────────────────────────────────────────
  # KVM/libvirt + Podman + microvm.nix host support. Guest definitions (the
  # Blocky resolver microVM) are added once the host is verified booting clean.
  mySystem.hypervisor.enable = true;

  # ── Apple hardware quirks ─────────────────────────────────────────────────
  # Intel MBP uses Apple EFI — systemd-boot works but some firmware vars may be
  # read-only. server-common sets canTouchEfiVariables true; override to false.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  system.stateVersion = "25.05";
}
