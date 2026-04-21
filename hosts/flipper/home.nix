{ config, self, pkgs, ... }: {
  # Set to the Home Manager release you first activated on this host.
  # Do not change this after the first activation.
  home.stateVersion = "25.05";

  # myHome.desktopHyprland.enable = true;  # temporarily on KDE
  myHome.firefox.enable         = true;
  myHome.tablet.enable          = true;
  myHome.mpv.enable             = true;
  # Wrapped program derivations (nix-wrapper-modules — config baked in)
  home.packages = with self.packages.${pkgs.stdenv.hostPlatform.system}; [
    zathura
    # foot     # Hyprland terminal — not needed on KDE (use Konsole)
    # rofi     # Hyprland launcher — not needed on KDE
    # waybar   # Hyprland bar — not needed on KDE
    fish
    okular
  ];
  xdg.mimeApps.defaultApplications."application/pdf" = "org.pwmt.zathura.desktop";
  myHome.imv.enable             = true;
  myHome.mpd.enable             = true;
  myHome.nas.enable             = true;
  myHome.yazi.enable		= true;
  # myHome.hyprshot.enable = true;  # Hyprland screenshot tool — not needed on KDE

  myHome.bearing = {
    enable       = true;
    terminal     = "konsole";  # foot while on Hyprland; konsole while on KDE
    ntfy.server  = "https://ntfy.vimba-stairs.ts.net";
  };

  services.poweralertd.enable = true;
}
