{ config, self, pkgs, ... }: {
  # Set to the Home Manager release you first activated on this host.
  # Do not change this after the first activation.
  home.stateVersion = "25.05";

  myHome.desktopHyprland.enable = true;
  myHome.firefox.enable         = true;
  myHome.tablet.enable          = true;
  myHome.mpv.enable             = true;
  # Wrapped program derivations (nix-wrapper-modules — config baked in)
  home.packages = with self.packages.${pkgs.stdenv.hostPlatform.system}; [
    zathura
    foot
    rofi
    waybar
    fish
  ];
  xdg.mimeApps.defaultApplications."application/pdf" = "org.pwmt.zathura.desktop";
  myHome.imv.enable             = true;
  myHome.mpd.enable             = true;
  myHome.nas.enable             = true;
  myHome.yazi.enable		= true;
  myHome.hyprshot.enable	= true;

  myHome.bearing = {
    enable       = true;
    terminal     = "foot";
    ntfy.server  = "https://ntfy.vimba-stairs.ts.net";
  };

  services.poweralertd.enable = true;
}
