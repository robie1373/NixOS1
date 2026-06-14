{ lib, pkgs, self, ... }:
let
  selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};

  # nix-wrapper-modules creates a minimal wrapper derivation that does not
  # propagate the original niri package's share/ directory. Install the
  # wayland-session .desktop file explicitly so regreet can discover it.
  niriSession = pkgs.writeTextDir "share/wayland-sessions/niri.desktop" ''
    [Desktop Entry]
    Name=Niri
    Comment=A scrollable-tiling Wayland compositor
    Exec=${selfpkgs.niri}/bin/niri-session
    Type=Application
    DesktopNames=niri
  '';
in {
  # ReGreet: GTK4 graphical greeter running inside cage.
  # programs.regreet automatically reconfigures greetd's default_session
  # to run cage → regreet. Session discovery reads wayland-sessions .desktop
  # files; selfpkgs.niri ships niri.desktop with Exec=niri-session.
  programs.regreet = {
    enable = true;

    settings = {
      # Background DISABLED 2026-06-13 — regreet 0.4.0 loads the background via
      # GtkMediaFile, and GTK4 4.22 routes that through GStreamer (gst-plugins-bad
      # 1.26.11) even for a static PNG, which fatally aborts → greeter crash-loop →
      # no graphical login (diagnosed from the coredump backtrace:
      # gtk_media_file_new_for_filename → gtk_gst_media_file_open → gst_play_main →
      # g_log_abort). Re-enable when the upstream GTK4/GStreamer media regression is
      # fixed, or once regreet loads static images as textures again.
      # background = {
      #   path = "/home/robie/nixos-config/media/redwoods.png";
      #   fit  = "Cover";
      # };

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

      default_session = {
        command = lib.mkForce "${selfpkgs.niri}/bin/niri-session";
        user    = lib.mkForce "robie";
      };
    };

    # Provide theme packages to cage's environment so regreet can find them.
    extraCss = ''
      window {
        background-color: alpha(#24273a, 0.85);
      }
    '';
  };

  # Ensure wayland-sessions .desktop files from all system packages are linked
  # into /run/current-system/sw/share/wayland-sessions where regreet/cage finds them.
  environment.pathsToLink = [ "/share/wayland-sessions" ];

  # Theme packages + niri session file for regreet to discover.
  environment.systemPackages = [
    niriSession
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
