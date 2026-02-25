{ config, ... }: {
  home.sessionVariables = {
    SSH_AUTH_SOCK="${config.home.homeDirectory}/.1password/agent.sock";
  };

  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host *
        IdentityAgent "${config.home.homeDirectory}/.1password/agent.sock"
    '';
  };
  
  
  programs.bash = {
    enable = true;
    initExtra = ''
      export SSH_AUTH_SOCK="/home/robie/.1password/agent.sock"
    '';
  };
  
  systemd.user.services.onepassword-gui = {
    Unit = {
      Description = "1Password GUI";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # This path points to the system-installed version only
      ExecStart = "/run/current-system/sw/bin/1password --silent --disable-gpu";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

}
