# hosts/langlab/hardware-configuration.nix
#
# Stub — nixos-anywhere generates the real file during install and merges it.
# This is enough for `nix flake check` to pass before the host exists.

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
