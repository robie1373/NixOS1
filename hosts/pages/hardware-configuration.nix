# hosts/pages/hardware-configuration.nix
#
# Minimal stub for the pages Proxmox KVM VM (identical platform to observ).
# nixos-anywhere merges real hardware detection during install; this stub is
# enough for `nix flake check` / eval before the VM exists.
#
# Proxmox KVM VM specifics:
#   - virtio disk (vda) — handled by disko.nix
#   - virtio NIC (ens18) — handled by configuration.nix
#   - UEFI boot — handled by server-common.nix (systemd-boot)

{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "ahci"
    "sd_mod"
  ];

  boot.kernelModules = [ "kvm-intel" ];
}
