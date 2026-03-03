{ config, ... }: {
  # Set to the Home Manager release you first activated on this host.
  # Do not change this after the first activation.
  home.stateVersion = "25.05";

  myHome.desktopHyprland.enable = true;
  myHome.firefox.enable         = true;
  myHome.tablet.enable          = true;
  myHome.entertainment.enable   = true;
}
