{ config, ... }: {
  # Set to the Home Manager release you first activated on this host.
  # Do not change this after the first activation.
  home.stateVersion = "25.05";

  myHome.desktopHyprland.enable = true;
  myHome.firefox.enable         = true;
  myHome.tablet.enable          = true;
  myHome.mpv.enable             = true;
  myHome.zathura.enable         = true;
  myHome.imv.enable             = true;
  myHome.mpd.enable             = true;
  myHome.nas.enable             = true;
  myHome.yazi.enable		= true;
  myHome.hyprshot.enable	= true;

  myHome.bearing = {
    enable   = true;
    terminal = "foot";
  };

  services.poweralertd.enable = true;
}
