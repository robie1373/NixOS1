{ lib, config, pkgs, ... }:

let
  cfg = config.myHome.teacha;
in {
  options.myHome.teacha = {
    enable = lib.mkEnableOption "Teacha ambient spaced repetition daemon";

    package = lib.mkOption {
      type        = lib.types.package;
      description = "The teacha-daemon package to install.";
    };

    channels = lib.mkOption {
      type    = lib.types.str;
      default = "desktop";
      description = "Comma-separated notification channels (desktop, ntfy, console).";
    };

    pollSeconds = lib.mkOption {
      type    = lib.types.int;
      default = 120;
      description = "Seconds between polls for due cards.";
    };

    ntfyUrl = lib.mkOption {
      type    = lib.types.nullOr lib.types.str;
      default = null;
      description = "ntfy topic URL for push notifications, e.g. https://ntfy.example.com/my-topic.";
    };
  };

  config = lib.mkIf cfg.enable {

    # notify-send is required for the desktop channel on Linux
    home.packages = [ pkgs.libnotify cfg.package ];

    systemd.user.services.teacha = {
      Unit = {
        Description = "Teacha ambient spaced repetition daemon";
        After       = [ "graphical-session.target" ];
      };
      Service = {
        Type      = "simple";
        ExecStart = lib.concatStringsSep " " (
          [ "${cfg.package}/bin/teacha-daemon"
            "--channels" cfg.channels
            "--poll-seconds" (toString cfg.pollSeconds)
          ] ++ lib.optional (cfg.ntfyUrl != null) "--ntfy-url ${cfg.ntfyUrl}"
        );
        Restart      = "on-failure";
        RestartSec   = "10s";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
