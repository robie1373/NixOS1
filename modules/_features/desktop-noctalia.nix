{ pkgs, self, ... }:
let
  selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};

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
  # No noctalia.cachix.org substituter: its founding reason (skip the ~2h Quickshell
  # build) died when noctalia 5.0.0 rewrote quickshell → native Wayland/GL. As a
  # GLOBAL, trusted, flaky third-party cache it added a per-path probe + supply-chain
  # trust surface to EVERY build and once 5xx-failed a vhost2 deploy. Removed 2026-07-22.
  # [[nixos-config]] / [[nixos-niri]].

  # power-profiles-daemon: noctalia's power-mode widget requires this.
  # bluetooth and upower already enabled in hosts/flipper/configuration.nix.
  services.power-profiles-daemon.enable = true;

  # ── Packages ─────────────────────────────────────────────────────────────────
  # Theme packages must be on the system profile so XDG_DATA_DIRS resolves them.
  # noctalia + desktop utilities moved here from _home/desktop-noctalia.nix
  # (HM removal Phase C — the HM noctalia module only added the package anyway;
  # niri spawns it by store path, noctalia owns its own config).
  # wlr-which-key was NOT migrated: orphaned since Mod+? (niri hotkey-overlay)
  # replaced it — removed per the hygiene rule.
  environment.systemPackages = [
    gtkTheme
    pkgs.papirus-icon-theme
    pkgs.catppuccin-cursors.macchiatoDark

    selfpkgs.noctalia
    pkgs.wl-clipboard     # wl-copy / wl-paste
    pkgs.grim             # screenshot tool
    pkgs.slurp            # interactive region selector
    pkgs.pavucontrol      # PulseAudio/PipeWire GUI
    pkgs.nwg-look         # GTK settings GUI
    pkgs.brightnessctl    # screen brightness
    pkgs.playerctl        # media player control

    # Mic mute toggle — F9 generates no OS events on this ASUS BIOS.
    # Mutes ALL PipeWire sources and syncs the LED.
    (pkgs.writeShellScriptBin "mic-toggle" ''
      if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
        NEW=0
      else
        NEW=1
      fi
      for id in $(wpctl status | awk '
        /Sources:/  { p=1 }
        /Filters:/  { p=0 }
        p && /[0-9]+\./ {
          for (i=1; i<=NF; i++)
            if ($i ~ /^[0-9]+\.$/) { gsub(/\./, "", $i); print $i; break }
        }
      '); do
        wpctl set-mute "$id" "$NEW"
      done
      echo "$NEW" > /sys/class/leds/platform::micmute/brightness
    '')
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
