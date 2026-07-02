{ ... }:
{
  home.enableNixpkgsReleaseCheck = false;

  home.stateVersion = "25.11";

  # HM removal in progress — firefox moved to _features/firefox.nix (Phase C).
  # Remaining HM surface: _home/common.nix (Phase D).
}
