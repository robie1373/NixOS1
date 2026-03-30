{ self, pkgs, ... }: {
# This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  myHome.desktopHyprland.enable = true;
  myHome.firefox.enable         = true;

  # Wrapped program derivations (nix-wrapper-modules — config baked in)
  home.packages = with self.packages.${pkgs.system}; [
    foot
    rofi
    waybar
    fish
  ];
}
