{ config, pkgs, osConfig, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "robie";
  home.homeDirectory = "/home/robie";

  # In your home.nix
  home.shellAliases = {
    ll = "ls -lh";
    la = "ls -ah";
    #vim = "nvim";

    rebuild = "nh os switch /home/robie/nixos-config";
    build   = "nh os build /home/robie/nixos-config";
    ntest   = "nh os test /home/robie/nixos-config";
    gc = "sudo nix-env --delete-generations $argv[1] --profile /nix/var/nix/profiles/system && nix-env --delete-generations $argv[1] && sudo nix-collect-garbage";
    #update = "sudo nixos-rebuild switch";
    gs = "git status";
  };

  # nix-index: pre-built package index for command-not-found + comma
  # comma: run any nixpkgs binary without installing it: ", ffmpeg ..."
  programs.nix-index-database.comma.enable = true;
  programs.nix-index.enable = true;

    # Configure git
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "robie1373";
        email = "robie1373@gmail.com";
      };
    };
  };

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    git-secrets
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/robie/etc/profile.d/hm-session-vars.sh
  #

  home.sessionVariables = {
    # EDITOR = "emacs";
  };


}
