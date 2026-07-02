{ lib, config, pkgs, inputs, ... }:
# Teacha ambient spaced-repetition daemon — system-level port of
# modules/_home/teacha.nix (HM removal Phase B). Disabled by default, matching
# the prior HM state (myHome.teacha.enable = false on flipper). Enable with:
#   mySystem.teacha.enable = true;
let
  cfg = config.mySystem.teacha;
in {
  options.mySystem.teacha = {
    enable = lib.mkEnableOption "Teacha ambient spaced repetition daemon";

    package = lib.mkOption {
      type        = lib.types.package;
      default     = inputs.teacha.packages.${pkgs.stdenv.hostPlatform.system}.teacha-daemon;
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
    environment.systemPackages = [ pkgs.libnotify cfg.package ];

    systemd.user.services.teacha = {
      description = "Teacha ambient spaced repetition daemon";
      after       = [ "graphical-session.target" ];
      wantedBy    = [ "graphical-session.target" ];
      serviceConfig = {
        Type      = "simple";
        ExecStart = lib.concatStringsSep " " (
          [ "${cfg.package}/bin/teacha-daemon"
            "--channels" cfg.channels
            "--poll-seconds" (toString cfg.pollSeconds)
          ] ++ lib.optional (cfg.ntfyUrl != null) "--ntfy-url ${cfg.ntfyUrl}"
        );
        Restart    = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
