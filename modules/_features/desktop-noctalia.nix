{ pkgs, ... }:
let
  # ── GTK/Qt theming (moved out of Home Manager, Phase A of HM removal) ────────
  # HM's clobber guard made every nixos-rebuild fail when a foreign gtk.css
  # appeared; noctalia rewrites gtk.css at login to inject `@import "noctalia.css"`,
  # so the fight was permanent. tmpfiles `L+` rules force-replace with no guard,
  # and our gtk.css already contains noctalia's import so it has nothing to add.
  gtkThemeName = "catppuccin-macchiato-mauve-standard+rimless";
  gtkTheme = pkgs.catppuccin-gtk.override {
    accents = [ "mauve" ];
    size    = "standard";
    tweaks  = [ "rimless" ];  # catppuccin-gtk 1.0.3 uses lowercase+plus naming
    variant = "macchiato";
  };
  iconThemeName   = "Papirus-Dark";
  cursorThemeName = "Catppuccin-Macchiato-Dark-Cursors";
  cursorSize      = 24;

  gtk3SettingsIni = pkgs.writeText "gtk3-settings.ini" ''
    [Settings]
    gtk-application-prefer-dark-theme=1
    gtk-cursor-theme-name=${cursorThemeName}
    gtk-cursor-theme-size=${toString cursorSize}
    gtk-icon-theme-name=${iconThemeName}
    gtk-theme-name=${gtkThemeName}
  '';

  gtk4SettingsIni = pkgs.writeText "gtk4-settings.ini" ''
    [Settings]
    gtk-cursor-theme-name=${cursorThemeName}
    gtk-cursor-theme-size=${toString cursorSize}
    gtk-icon-theme-name=${iconThemeName}
    gtk-theme-name=${gtkThemeName}
  '';

  gtk4Css = pkgs.writeText "gtk4-gtk.css" ''
    /**
     * GTK 4 reads the theme configured by gtk-theme-name, but ignores it.
     * It does however respect user CSS, so import the theme from here.
    **/
    @import url("file://${gtkTheme}/share/themes/${gtkThemeName}/gtk-4.0/gtk.css");

    @import url("noctalia.css");
  '';

  gtkrc2 = pkgs.writeText "gtkrc-2.0" ''
    gtk-cursor-theme-name = "${cursorThemeName}"
    gtk-cursor-theme-size = ${toString cursorSize}
    gtk-icon-theme-name = "${iconThemeName}"
    gtk-theme-name = "${gtkThemeName}"
  '';
in
{
  # Noctalia binary cache — avoids building Quickshell from source (~2h on flipper).
  nix.settings = {
    extra-substituters      = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  # power-profiles-daemon: noctalia's power-mode widget requires this.
  # bluetooth and upower already enabled in hosts/flipper/configuration.nix.
  services.power-profiles-daemon.enable = true;

  # ── GTK theme files ──────────────────────────────────────────────────────────
  # Theme packages must be on the system profile so XDG_DATA_DIRS resolves them.
  environment.systemPackages = [
    gtkTheme
    pkgs.papirus-icon-theme
    pkgs.catppuccin-cursors.macchiatoDark
  ];

  systemd.user.tmpfiles.users.robie.rules = [
    "d %h/.config/gtk-3.0 0755 - - -"
    "d %h/.config/gtk-4.0 0755 - - -"
    "L+ %h/.config/gtk-3.0/settings.ini - - - - ${gtk3SettingsIni}"
    "L+ %h/.config/gtk-4.0/settings.ini - - - - ${gtk4SettingsIni}"
    "L+ %h/.config/gtk-4.0/gtk.css - - - - ${gtk4Css}"
    "L+ %h/.gtkrc-2.0 - - - - ${gtkrc2}"
  ];

  # Dark mode for libadwaita apps (GTK4) — system dconf profile replaces HM's
  # dconf.settings. (gtk-application-prefer-dark-theme only covers GTK3.)
  programs.dconf = {
    enable = true;
    profiles.user.databases = [{
      settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
    }];
  };

  # Qt follows GTK. NixOS "gtk2" = qtstyleplugins, the same backend HM's
  # deprecated platformTheme.name = "gtk" used.
  qt = {
    enable = true;
    platformTheme = "gtk2";
  };
}
