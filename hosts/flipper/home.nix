{ ... }: {
  # Set to the Home Manager release you first activated on this host.
  # Do not change this after the first activation.
  home.stateVersion = "25.05";

  # HM removal in progress. Remaining HM surface: _home/common.nix (Phase D)
  # and _home/1password.nix (Phase D reference — not imported).
  # Phase B (2026-07-02): bearing, poweralertd, ifuse, desktop packages,
  #   nodejs/QMD env, pdf mime -> _features / hosts/flipper/configuration.nix.
  # Phase C (2026-07-02): firefox -> _features/firefox.nix, mpd/ncmpcpp ->
  #   _features/mpd.nix, noctalia pkg + utilities + mic-toggle ->
  #   _features/desktop-noctalia.nix.
  # Removed (unused; reinstatement documented in the Ledger): teacha,
  #   waybar, wlr-which-key, dunst.
}
