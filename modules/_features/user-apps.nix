{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    anki-bin
    obsidian
    yazi

    # mpv with uosc UI + sponsorblock, Wayland native
    (mpv.override {
      scripts = with mpvScripts; [ uosc sponsorblock ];
      mpv-unwrapped = mpv-unwrapped.override { waylandSupport = true; };
    })

    # imv: lightweight Wayland image viewer
    imv
  ];

  # imv: Catppuccin Macchiato theme. imv checks $XDG_CONFIG_DIRS,
  # which includes /etc/xdg/ on NixOS.
  environment.etc."xdg/imv/config".text = ''
    [options]
    background        = 24273a
    overlay_font      = JetBrainsMono Nerd Font:13
    overlay_text_color       = cad3f5ff
    overlay_background_color = 1e2030cc
    slideshow_duration = 0

    [aliases]
    q = quit
  '';

  # imv as default image viewer; zathura as default PDF viewer
  xdg.mime.defaultApplications = {
    "image/jpeg"    = "imv.desktop";
    "image/png"     = "imv.desktop";
    "image/gif"     = "imv.desktop";
    "image/webp"    = "imv.desktop";
    "image/tiff"    = "imv.desktop";
    "image/bmp"     = "imv.desktop";
    "image/svg+xml" = "imv.desktop";
  };
}
