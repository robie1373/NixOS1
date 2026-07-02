{ ... }: {
  # Set to the Home Manager release you first activated on this host.
  # Do not change this after the first activation.
  home.stateVersion = "25.05";

  # Remaining HM surface after Phase B of the HM removal — Phase C/D targets:
  myHome.firefox.enable = true;
  myHome.mpd.enable     = true;

  # Migrated out in Phase B (2026-07-02):
  #   wrapped desktop packages   -> _features/desktop-niri.nix
  #   nodejs_22 + QMD env/PATH   -> hosts/flipper/configuration.nix
  #   pdf mime default           -> _features/user-apps.nix
  #   myHome.bearing             -> _features/bearing.nix
  #   services.poweralertd       -> hosts/flipper/configuration.nix
  # Removed (unused; reinstatement documented in ledger teacha.md): teacha
}
