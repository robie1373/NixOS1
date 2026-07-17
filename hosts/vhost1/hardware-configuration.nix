# hosts/vhost1/hardware-configuration.nix
#
# GENERATED from the live hardware 2026-07-17 (`nixos-generate-config
# --show-hardware-config --no-filesystems` on the running box, per this file's
# own executor note) — replaces the 2026-07-06 hand-written version. Only delta
# from the guess: + sr_mod. Hardware facts: i7-6700K Skylake, 16 GB, UEFI,
# 970 EVO Plus 1TB NVMe (disko owns it), 870 EVO 2TB SATA (present, unmounted —
# carries an unexamined ext4 partition, see ledger proxmox.md), RTX 2070
# (HDMI feeds the JetKVM). A dying third SSD was removed 2026-07-17.
# Filesystem declarations stripped — disko.nix owns partition/mount layout.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Headless hypervisor; the 2070's firmware framebuffer is the console (JetKVM).
  # nouveau is never wanted here (this card has only ever run the proprietary
  # driver — fivenix precedent) and the card's USB-C controller spams i2c/ucsi
  # probe failures on every boot. Blacklisted 2026-07-17.
  boot.blacklistedKernelModules = [ "nouveau" "ucsi_ccg" "i2c_nvidia_gpu" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
