{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "flipper";

  mySystem.audio.enable           = true;
  #mySystem.desktopKde.enable      = false;
  mySystem.desktopHyprland.enable = true;
  #mySystem.vmGuest.enable         = false;

  # Resume device for hibernate — must match swap partition label in disko.nix
  boot.resumeDevice = "/dev/disk/by-partlabel/swap";

  environment.systemPackages = with pkgs; [
    wget
    tree
  ];

  # Enable CUPS to print documents.
  services.printing.enable = false;

  # Set to the NixOS release you first installed this system with.
  # Do not change this after the first install.
  system.stateVersion = "25.11";
}
