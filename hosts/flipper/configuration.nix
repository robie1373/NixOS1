{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "flipper";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  mySystem.audio.enable           = true;
  #mySystem.desktopKde.enable      = false;
  mySystem.desktopHyprland.enable = true;

  # Resume device for hibernate — disko labels swap as "disk-main-swap" (disk name + partition name)
  boot.resumeDevice = "/dev/disk/by-partlabel/disk-main-swap";

  environment.systemPackages = with pkgs; [
    wget
    tree
  ];

#  hardware.firmware = [
#    (pkgs.runCommand "tas2781-firmware-fix" {} '' 
#      mkdir -p $out/lib/firmware 
#      ln -s ${pkgs.linux-firmware}/lib/firmware/TAS2XXX10A40.bin.zst \
#      $out/lib/firmware/TAS2XXX10A4.bin.zst 
#    '')
#  ];

  # Enable CUPS to print documents.
  services.printing.enable = false;

  # Set to the NixOS release you first installed this system with.
  # Do not change this after the first install.
  system.stateVersion = "25.11";
}
