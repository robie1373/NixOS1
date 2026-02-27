 { lib, config, pkgs, ... }:                                                              
                                                                                           
  {               
    options.myHome.firefox.enable =
      lib.mkEnableOption "Firefox home config";

    config = lib.mkIf config.myHome.firefox.enable {

      programs.firefox = {
        enable = true;

        profiles.default = {
          settings = {
            "browser.startup.homepage" = "about:blank";
            "browser.newtabpage.enabled" = false;
            "privacy.trackingprotection.enabled" = true;
            "toolkit.telemetry.enabled" = false;
          };
        };
      };

    };
  }
