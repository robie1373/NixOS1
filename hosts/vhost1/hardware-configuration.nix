# hosts/vhost1/hardware-configuration.nix
#
# vhost1 (formerly pve) — Intel Core i7-6700K (Skylake), NVMe boot, UEFI.
# Facts confirmed off the running pve host 2026-07-05 (lsblk / cpuinfo / EFI check):
#   boot disk : Samsung 970 EVO Plus 1TB NVMe (nvme0n1) — disko owns it
#   also present: Samsung 870 EVO 2TB SATA (sda) — left alone, NOT mounted here
#   CPU       : i7-6700K, Skylake (x86-64-v3 capable — better than vhost2's Haswell)
#   RAM       : 16 GB   |   firmware: UEFI
# Filesystem declarations stripped — disko.nix owns partition/mount layout.
#
# ⚠️ EXECUTOR: regenerate with `nixos-generate-config --no-filesystems` from the
# installer/kexec environment at conversion time and reconcile against this file —
# authored from remote probing, not generated on the metal. NVMe/UEFI desktop-board
# profile; should be close.

{ config, lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # nvme = the boot disk; ahci/sd_mod cover the SATA controller (870 EVO present
  # but unmounted); xhci_pci/usb_* for the install/rescue USB.
  boot.initrd.availableKernelModules = [
    "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules        = [ "kvm-intel" ];   # Skylake VT-x; hypervisor.nix also sets this
  boot.extraModulePackages  = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
