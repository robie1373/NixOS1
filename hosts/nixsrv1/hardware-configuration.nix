# hosts/nixsrv1/hardware-configuration.nix
#
# Generated from Intel MBP (i7-3820QM) via nixos-generate-config 2026-05-09.
# Filesystem declarations stripped — disko.nix owns partition/mount layout.
# kvm-intel confirmed present (hardware virtualization ready).

{ config, lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci" "ehci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" "sr_mod" "sdhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules        = [ "kvm-intel" ];
  boot.extraModulePackages  = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
