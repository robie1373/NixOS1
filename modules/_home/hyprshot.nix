{ pkgs, lib, config, ... }:

let
  cfg = config.myHome.hyprshot;
in
{
  options.myHome.hyprshot.enable = lib.mkEnableOption "Hyprshot screenshot tool";

  config = lib.mkIf cfg.enable {
    # 1. Install the packages directly since 'programs.grim' etc. don't exist
    home.packages = with pkgs; [
      hyprshot
      grim
      slurp
      wl-clipboard
    ];

    # 2. Add the binds directly to your Hyprland configuration
    wayland.windowManager.hyprland.settings = {
      bind = [
        # Take a screenshot of the active window
        "SUPER, Print, exec, ${lib.getExe pkgs.hyprshot} -m window"
        # Take a screenshot of the entire screen
        ", Print, exec, ${lib.getExe pkgs.hyprshot} -m output"
        # Take a screenshot of a selected region
        "SHIFT, Print, exec, ${lib.getExe pkgs.hyprshot} -m region"
      ];
    };

    # 3. Use environment variables to set the output directory
    home.sessionVariables = {
      HYPRSHOT_DIR = "${config.home.homeDirectory}/images/screenshots";
    };
  };
}

