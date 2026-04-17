{ ... }:
{
  # home-manager follows nixpkgs-unstable (26.05) while this host uses
  # nixpkgs-stable (25.11). useGlobalPkgs = true means HM uses stable pkgs
  # from the system, so the mismatch is harmless — suppress the warning.
  home.enableNixpkgsReleaseCheck = false;

  home.stateVersion = "25.11";
}
