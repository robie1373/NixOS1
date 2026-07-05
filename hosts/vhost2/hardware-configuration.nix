# hosts/vhost2/hardware-configuration.nix
#
# vhost2 (formerly pve2) — Intel Core i5-4590 (Haswell), SATA SSD, UEFI boot.
# Facts confirmed off the running pve2 host 2026-07-04 (lsblk / cpuinfo / EFI check).
# Filesystem declarations stripped — disko.nix owns partition/mount layout.
#
# ⚠️ EXECUTOR: regenerate with `nixos-generate-config --no-filesystems` from the
# installer/kexec environment at conversion time and reconcile against this file —
# this was authored from remote probing, not generated on the metal. The module
# set below is the standard SATA/UEFI desktop-board profile and should be close.

{ config, lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci" "ehci_pci" "ahci" "usbhid" "usb_storage" "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules        = [ "kvm-intel" ];   # Haswell VT-x; hypervisor.nix also sets this
  boot.extraModulePackages  = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
