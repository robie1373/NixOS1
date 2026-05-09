# modules/_system/hypervisor.nix
#
# Baseline for a NixOS host that runs VMs, microVMs, and containers.
# Imported by nixsrv1. Does NOT import server-common — that's separate.
#
# KVM/libvirt: full VM management via virsh.
# Podman: rootless-capable containers (dockerCompat alias provided).
# microvm.nix: lightweight type-1 VMs — requires microvm flake input in
#              the host's nixosConfigurations declaration (see modules/hosts/nixsrv1/default.nix).
#
# Individual microVM definitions live in the importing host config, not here.

{ config, pkgs, lib, ... }:

{
  options.mySystem.hypervisor = {
    enable = lib.mkEnableOption "KVM/libvirt + Podman + microvm.nix hypervisor stack";
  };

  config = lib.mkIf config.mySystem.hypervisor.enable {

    # ── KVM / libvirt ─────────────────────────────────────────────────────
    virtualisation.libvirtd = {
      enable           = true;
      qemu.ovmf.enable = true;
      qemu.runAsRoot   = false;
    };

    # ── Podman ────────────────────────────────────────────────────────────
    virtualisation.podman = {
      enable       = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    # ── microvm.nix host support ──────────────────────────────────────────
    # Enables host infrastructure for launching microVMs.
    # The microvm flake input must be in the host module declaration.
    microvm.host.enable = true;

    # ── Kernel modules ────────────────────────────────────────────────────
    boot.kernelModules = [ "kvm-intel" ];

    # ── Packages ──────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      virtiofsd
      qemu_kvm
    ];

    # ── User access ───────────────────────────────────────────────────────
    users.users.root.extraGroups = [ "libvirtd" "kvm" ];
  };
}
