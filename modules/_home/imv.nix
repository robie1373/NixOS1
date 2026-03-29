{ lib, config, pkgs, ... }:

{
  options.myHome.imv.enable =
    lib.mkEnableOption "imv image viewer";

  config = lib.mkIf config.myHome.imv.enable {

    home.packages = [ pkgs.imv ];

    # ── Catppuccin Macchiato ────────────────────────────────────────────
    xdg.configFile."imv/config".text = ''
      [options]
      background        = 24273a
      overlay_font      = JetBrainsMono Nerd Font:13
      overlay_text_color       = cad3f5ff
      overlay_background_color = 1e2030cc
      slideshow_duration = 0

      [aliases]
      q = quit
    '';

    # Register imv as the default handler for common image types
    xdg.mimeApps.defaultApplications = {
      "image/jpeg"   = "imv.desktop";
      "image/png"    = "imv.desktop";
      "image/gif"    = "imv.desktop";
      "image/webp"   = "imv.desktop";
      "image/tiff"   = "imv.desktop";
      "image/bmp"    = "imv.desktop";
      "image/svg+xml" = "imv.desktop";
    };
  };
}
