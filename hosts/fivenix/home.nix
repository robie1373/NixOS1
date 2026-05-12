{ ... }:
{
  # home-manager follows nixpkgs-unstable (26.05) while this host uses
  # nixpkgs-stable (25.11). useGlobalPkgs = true means HM uses stable pkgs
  # from the system, so the mismatch is harmless — suppress the warning.
  home.enableNixpkgsReleaseCheck = false;

  home.stateVersion = "25.11";

  # KDE screen lock disabled — session crashes on USB audio device disconnect
  # cause SDDM to restart and show what looks like a lock screen. Autolock was
  # already set to "never" in System Settings but KDE overwrites the file;
  # managing it here prevents that. LockOnResume=false keeps it off after suspend.
  xdg.configFile."kscreenlockerrc".text = ''
    [Daemon]
    Autolock=false
    LockGrace=0
    LockOnResume=false
    Timeout=0
  '';
}
