{ ... }: {
  # Set to the Home Manager release you first activated on this host.
  # Do not change this after the first activation.
  home.stateVersion = "25.05";

  myHome.firefox.enable = true;
  xdg.mimeApps.defaultApplications."application/pdf" = "org.pwmt.zathura.desktop";
  myHome.imv.enable = true;
  myHome.mpd.enable = true;
}
