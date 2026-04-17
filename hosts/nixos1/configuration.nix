{ config, pkgs, self, ... }:

{
  imports =
    [ 
      ./hardware-configuration.nix
    ];

  networking.hostName = "nixos1"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.


  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    tree
    ollama		# CLI client — server runs on fivenix (see OLLAMA_HOST below)
  ];

  environment.sessionVariables.OLLAMA_HOST = "http://192.168.7.137:11434";


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  programs.fish.package = self.packages.${pkgs.stdenv.hostPlatform.system}.fish;

  system.stateVersion = "25.11"; # Did you read the comment?

}
