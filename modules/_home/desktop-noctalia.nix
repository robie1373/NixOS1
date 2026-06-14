{ lib, config, inputs, pkgs, self, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  # ════════════════════════════════════════════════════════════════════════
  # NOCTALIA — desktop shell (bar, notifications, lock, wallpaper, launcher)
  # Spawned by niri via spawn-at-startup; not managed by systemd (deprecated).
  # ════════════════════════════════════════════════════════════════════════
  # Noctalia owns its own config files — no settings/colors managed here.
  # Nix manages only the package; noctalia writes its config itself.
  #
  # NOTE (2026-06-14): migrated to noctalia v5 (native Wayland/GL rewrite). Option
  # renamed programs.noctalia-shell -> programs.noctalia; binary renamed
  # noctalia-shell -> noctalia (see niri spawn). v5 won't read v4 config — expect
  # to reconfigure the bar via its settings menu.
  programs.noctalia.enable = true;

  # ════════════════════════════════════════════════════════════════════════
  # GTK THEME
  # ════════════════════════════════════════════════════════════════════════
  gtk = {
    enable = true;

    theme = {
      # catppuccin-gtk 1.0.3 uses lowercase+plus naming convention.
      name    = "catppuccin-macchiato-mauve-standard+rimless";
      package = pkgs.catppuccin-gtk.override {
        accents = [ "mauve" ];
        size    = "standard";
        tweaks  = [ "rimless" ];
        variant = "macchiato";
      };
    };

    iconTheme = {
      name    = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    cursorTheme = {
      name    = "Catppuccin-Macchiato-Dark-Cursors";
      package = pkgs.catppuccin-cursors.macchiatoDark;
      size    = 24;
    };

    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    # gtk4: libadwaita ignores gtk-application-prefer-dark-theme; use dconf instead.
    # Silence HM 26.05 stateVersion warning; keep legacy behavior (gtk4 = gtk3 theme).
    gtk4.theme = config.gtk.theme;
  };

  # Dark mode for libadwaita apps (GTK4). This is the correct mechanism.
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  # ════════════════════════════════════════════════════════════════════════
  # QT THEME
  # ════════════════════════════════════════════════════════════════════════
  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };

  # ════════════════════════════════════════════════════════════════════════
  # ADDITIONAL PACKAGES
  # ════════════════════════════════════════════════════════════════════════
  home.packages = with pkgs; [
    wlr-which-key    # keybind cheatsheet popup (Mod+/)
    wl-clipboard     # wl-copy / wl-paste
    grim             # screenshot tool
    slurp            # interactive region selector
    pavucontrol      # PulseAudio/PipeWire GUI
    nwg-look         # GTK settings GUI
    brightnessctl    # screen brightness
    playerctl        # media player control

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

  # ════════════════════════════════════════════════════════════════════════
  # WLR-WHICH-KEY — keybind cheatsheet popup (Mod+/)
  # ════════════════════════════════════════════════════════════════════════
  xdg.configFile."wlr-which-key/config.yaml".text = ''
    font: "JetBrainsMono Nerd Font 14"
    background: "#24273a"
    color: "#cad3f5"
    border: "#8aadf4"
    border_width: 2
    corner_r: 10
    padding: 20
    margin_top: 20
    margin_right: 20
    margin_bottom: 20
    margin_left: 20
    anchor: center

    menu:
      - key: Return
        desc: "terminal"
        cmd: "${self.packages.${pkgs.stdenv.hostPlatform.system}.foot}/bin/foot"
      - key: d
        desc: "app launcher"
        cmd: "${self.packages.${pkgs.stdenv.hostPlatform.system}.rofi}/bin/rofi -show drun"
      - key: e
        desc: "window switcher"
        cmd: "${self.packages.${pkgs.stdenv.hostPlatform.system}.rofi}/bin/rofi -show window"
      - key: w
        desc: "windows →"
        submenu:
          - key: u
            desc: "close"
            cmd: "niri msg action close-window"
          - key: f
            desc: "fullscreen"
            cmd: "niri msg action fullscreen-window"
          - key: v
            desc: "float toggle"
            cmd: "niri msg action toggle-window-floating"
      - key: m
        desc: "media →"
        submenu:
          - key: u
            desc: "vol +"
            cmd: "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
            keep_open: true
          - key: d
            desc: "vol -"
            cmd: "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
            keep_open: true
          - key: m
            desc: "mute toggle"
            cmd: "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          - key: p
            desc: "play/pause"
            cmd: "playerctl play-pause"
          - key: n
            desc: "next track"
            cmd: "playerctl next"
  '';

  # ════════════════════════════════════════════════════════════════════════
  # IPHONE — auto-mount via ifuse (triggered by udev on plug-in)
  # ════════════════════════════════════════════════════════════════════════
  systemd.user.services.ifuse-mount = {
    Unit.Description = "Mount iPhone via ifuse";
    Service = {
      Type            = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre    = "${pkgs.coreutils}/bin/mkdir -p %h/mnt/iphone";
      ExecStart       = "${pkgs.ifuse}/bin/ifuse %h/mnt/iphone";
    };
  };

  systemd.user.services.ifuse-unmount = {
    Unit.Description = "Unmount iPhone";
    Service = {
      Type      = "oneshot";
      ExecStart = "/run/wrappers/bin/fusermount -u %h/mnt/iphone";
    };
  };
}
