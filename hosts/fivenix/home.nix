{ ... }:
{
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
