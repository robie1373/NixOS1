{ lib, config, pkgs, ... }:

# Teacha ambient spaced repetition daemon.
# Migrated from _home/teacha.nix (HM) to a NixOS system module (2026-05-20).
# Key changes: home.packages → environment.systemPackages; systemd.user.* unchanged.

let
  cfg = config.teacha;
in {
  options.teacha = {
    enable = lib.mkEnableOption "Teacha ambient spaced repetition daemon";

    package = lib.mkOption {
      type        = lib.types.package;
      description = "The teacha-daemon package to install.";
    };

    channels = lib.mkOption {
      type    = lib.types.str;
      default = "desktop";
    };

    pollSeconds = lib.mkOption {
      type    = lib.types.int;
      default = 120;
    };

    ntfyUrl = lib.mkOption {
      type    = lib.types.nullOr lib.types.str;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {

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
