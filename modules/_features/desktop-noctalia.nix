{ pkgs, self, lib, ... }:
let
  selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};

  gtkThemePkg = pkgs.catppuccin-gtk.override {
    accents = [ "mauve" ];
    size    = "standard";
    tweaks  = [ "rimless" ];
    variant = "macchiato";
  };

  gtk3Ini = pkgs.writeText "gtk3-settings.ini" ''
    [Settings]
    gtk-theme-name=catppuccin-macchiato-mauve-standard+rimless
    gtk-icon-theme-name=Papirus-Dark
    gtk-cursor-theme-name=Catppuccin-Macchiato-Dark-Cursors
    gtk-cursor-theme-size=24
    gtk-application-prefer-dark-theme=1
  '';

  gtk2Rc = pkgs.writeText "gtkrc-2.0" ''
    gtk-theme-name="catppuccin-macchiato-mauve-standard+rimless"
    gtk-icon-theme-name="Papirus-Dark"
    gtk-cursor-theme-name="Catppuccin-Macchiato-Dark-Cursors"
    gtk-cursor-theme-size=24
  '';

  gtk4Ini = pkgs.writeText "gtk4-settings.ini" ''
    [Settings]
    gtk-application-prefer-dark-theme=1
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
  services.power-profiles-daemon.enable = true;

  # ── Noctalia + desktop tools ─────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    selfpkgs.noctalia
    wlr-which-key
    wl-clipboard
    grim
    slurp
    pavucontrol
    nwg-look
    brightnessctl
    playerctl
    # GTK / icon / cursor theme packages
    gtkThemePkg
    papirus-icon-theme
    catppuccin-cursors.macchiatoDark
    # Mic mute toggle — F9 generates no OS events on this ASUS BIOS.
    # Mutes ALL PipeWire sources and syncs the LED.
    (writeShellScriptBin "mic-toggle" ''
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

  # ── Qt theming ────────────────────────────────────────────────────────────────
  qt.enable        = true;
  qt.platformTheme = "gtk2";

  # ── dconf: dark mode for libadwaita (GTK4) apps ───────────────────────────────
  # gtk4.extraConfig.gtk-application-prefer-dark-theme is ignored by libadwaita;
  # dconf is the correct mechanism.
  programs.dconf.profiles.user.databases = lib.mkAfter [{
    settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  }];

  # ── GTK theming via user tmpfiles ─────────────────────────────────────────────
  # L+ removes and recreates the symlink on each activation.
  # catppuccin-gtk 1.0.3 naming: lowercase+plus (catppuccin-macchiato-mauve-standard+rimless).
  systemd.user.tmpfiles.rules = [
    "L+ %h/.config/gtk-3.0/settings.ini - - - - ${gtk3Ini}"
    "L+ %h/.gtkrc-2.0                   - - - - ${gtk2Rc}"
    "L+ %h/.config/gtk-4.0/settings.ini - - - - ${gtk4Ini}"
  ];

  # ── iPhone mounting (user services triggered by udev) ─────────────────────────
  # udev rules in hosts/flipper/configuration.nix fire SYSTEMD_USER_WANTS on plug/unplug.
  systemd.user.services.ifuse-mount = {
    description = "Mount iPhone via ifuse";
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStartPre    = "${pkgs.coreutils}/bin/mkdir -p %h/mnt/iphone";
      ExecStart       = "${pkgs.ifuse}/bin/ifuse %h/mnt/iphone";
    };
  };

  systemd.user.services.ifuse-unmount = {
    description = "Unmount iPhone";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = "/run/wrappers/bin/fusermount -u %h/mnt/iphone";
    };
  };
}
