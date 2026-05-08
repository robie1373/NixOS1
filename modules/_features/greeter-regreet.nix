{ lib, pkgs, self, ... }:
let selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
in {
  # ReGreet: GTK4 graphical greeter running inside cage.
  # programs.regreet automatically reconfigures greetd's default_session
  # to run cage → regreet. Session discovery reads wayland-sessions .desktop
  # files; selfpkgs.niri ships niri.desktop with Exec=niri-session.
  programs.regreet = {
    enable = true;

    settings = {
      background = {
        path = "/home/robie/nixos-config/media/redwoods.png";
        fit  = "Cover";
      };

      GTK = {
        application_prefer_dark_theme = lib.mkForce true;
        cursor_theme_name = lib.mkForce "Catppuccin-Macchiato-Dark-Cursors";
        font_name         = lib.mkForce "JetBrainsMono Nerd Font 12";
        icon_theme_name   = lib.mkForce "Papirus-Dark";
        theme_name        = lib.mkForce "catppuccin-macchiato-mauve-standard+rimless";
      };

      commands = {
        reboot   = [ "systemctl" "reboot" ];
        poweroff = [ "systemctl" "poweroff" ];
      };
    };

    # Provide theme packages to cage's environment so regreet can find them.
    extraCss = ''
      window {
        background-color: alpha(#24273a, 0.85);
      }
    '';
  };

  # Theme packages available in cage's environment for regreet to load.
  environment.systemPackages = [
    pkgs.papirus-icon-theme
    pkgs.catppuccin-cursors.macchiatoDark
    (pkgs.catppuccin-gtk.override {
      accents = [ "mauve" ];
      size    = "standard";
      tweaks  = [ "rimless" ];
      variant = "macchiato";
    })
  ];
}
