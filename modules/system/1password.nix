{ config, pkgs, ... }:

{
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "robie" ];
  };

  users.users.robie.extraGroups = [ "onepassword" ];

  # Allows the proprietary license
  nixpkgs.config.allowUnfree = true;
}
