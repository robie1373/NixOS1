{ ... }:
{
  programs._1password.enable = true;
  programs._1password-gui = {
    enable             = true;
    polkitPolicyOwners = [ "robie" ];
  };

  users.users.robie.extraGroups = [ "onepassword" ];

  # Allows the proprietary license
  nixpkgs.config.allowUnfree = true;

  # SSH_AUTH_SOCK — points SSH clients and git at the 1Password agent socket.
  # Written to /etc/environment via PAM; inherited by all sessions including
  # login shells, graphical sessions, and systemd user units.
  environment.sessionVariables.SSH_AUTH_SOCK = "/home/robie/.1password/agent.sock";

  # Belt-and-suspenders bash export. The original HM config had this because
  # home.sessionVariables alone did not cover all bash contexts (reason unknown,
  # do not assume redundant). Appends to /etc/bash.bashrc for interactive shells.
  programs.bash.interactiveShellInit = ''
    export SSH_AUTH_SOCK="/home/robie/.1password/agent.sock"
  '';

  # IdentityAgent in system ssh_config. SSH_AUTH_SOCK alone was NOT sufficient
  # on this system — the explicit IdentityAgent declaration was required.
  # Originally written to ~/.ssh/config by HM programs.ssh.matchBlocks.
  # After HM is removed there is no ~/.ssh/config, so this system config applies.
  # Do not remove without testing: ssh -T git@github.com AND git push.
  programs.ssh.extraConfig = ''
    Host *
      IdentityAgent /home/robie/.1password/agent.sock
  '';

  # 1Password GUI autostart. The GUI process IS the SSH agent —
  # without it, ~/.1password/agent.sock does not exist.
  # --disable-gpu: required — GPU acceleration caused session crashes on flipper.
  # --silent: start to tray only, no main window.
  systemd.user.services.onepassword-gui = {
    description = "1Password GUI";
    wantedBy    = [ "graphical-session.target" ];
    after       = [ "graphical-session.target" ];
    partOf      = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "/run/current-system/sw/bin/1password --silent --disable-gpu";
      Restart   = "on-failure";
    };
  };
}
