# hosts/dns2/hardware-configuration.nix
#
# Minimal stub for the dns2 Proxmox KVM VM.
# nixos-anywhere generates the real hardware-configuration.nix during install
# and merges it with what's here. This stub is enough for `nix flake check`
# to pass before the VM exists.
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
