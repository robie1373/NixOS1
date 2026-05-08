{ lib, config, pkgs, osConfig, self, ... }:

{
  options.myHome.desktopHyprland.enable =
    lib.mkEnableOption "Hyprland home config";

  config = lib.mkIf config.myHome.desktopHyprland.enable {

    # ════════════════════════════════════════════════════════════════════════
    # HYPRLAND — window manager config
    # ════════════════════════════════════════════════════════════════════════
    wayland.windowManager.hyprland = {
      enable = true;

      settings = {

        monitor = ",preferred,auto,1";

        # Programs launched once on startup
        # Use full store paths — PATH is not populated when Hyprland starts via greetd
        exec-once = [
          "${self.packages.${pkgs.stdenv.hostPlatform.system}.waybar}/bin/waybar"
          "${pkgs.swaybg}/bin/swaybg -i /home/robie/nixos-config/media/redwoods.png -m fill"
          # dunst and hypridle are managed as systemd user services — no exec-once needed
        ];

        # Modifier key: SUPER = the Windows/Command key
        "$mod" = "SUPER";

        # ── Keybinds ──────────────────────────────────────────────────────
        bind = [
          # Korean IM toggle — Alt_R is a modifier key; fcitx5 never sees it via Wayland IM
          # protocol. Intercept at compositor level instead and call fcitx5-remote directly.
          ", Alt_R, exec, ${pkgs.fcitx5}/bin/fcitx5-remote -t"

          # Apps
          "$mod, Return, exec, ${self.packages.${pkgs.stdenv.hostPlatform.system}.foot}/bin/foot"
          "$mod, D, exec, ${self.packages.${pkgs.stdenv.hostPlatform.system}.rofi}/bin/rofi -show drun"
          "$mod, E, exec, ${self.packages.${pkgs.stdenv.hostPlatform.system}.rofi}/bin/rofi -show window"

          # Window management
          "$mod, U, killactive,"
          "$mod, ], exit,"
          "$mod, F, fullscreen,"
          "$mod, V, togglefloating,"
          "$mod, P, pseudo,"         # dwindle: keep window size when tiling

          # Focus (vim-style)
          "$mod, h, movefocus, l"
          "$mod, l, movefocus, r"
          "$mod, k, movefocus, u"
          "$mod, j, movefocus, d"

          # Move windows
          "$mod SHIFT, h, movewindow, l"
          "$mod SHIFT, l, movewindow, r"
          "$mod SHIFT, k, movewindow, u"
          "$mod SHIFT, j, movewindow, d"

          # Workspaces 1–5
          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"

          # Move window to workspace
          "$mod SHIFT, 1, movetoworkspace, 1"
          "$mod SHIFT, 2, movetoworkspace, 2"
          "$mod SHIFT, 3, movetoworkspace, 3"
          "$mod SHIFT, 4, movetoworkspace, 4"
          "$mod SHIFT, 5, movetoworkspace, 5"

          # Screenshot (requires grim + slurp)
          ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"

          # Which-key popup
          "$mod, slash, exec, ${pkgs.wlr-which-key}/bin/wlr-which-key"

          # The Bearing — open a bearing session in a new terminal
          "$mod, B, exec, ${self.packages.${pkgs.stdenv.hostPlatform.system}.foot}/bin/foot -- bash -c 'cd ~/work && claude bearing; exec bash'"
        ];

        # Touchpad gestures
        gesture = [
          "3, right, dispatcher, sendshortcut, ALT, Right, activewindow"     # Browser forward
          "3, left, dispatcher, sendshortcut, ALT, Left, activewindow"       # Browser back
          "2, pinchout, dispatcher, sendshortcut, CTRL, equal, activewindow" # Increase font size
          "2, pinchin, dispatcher, sendshortcut, CTRL, minus, activewindow"  # Decrease font size
        ];

        # Mouse binds
        bindm = [
          "$mod, mouse:272, movewindow"    # SUPER + left-drag  = move
          "$mod, mouse:273, resizewindow"  # SUPER + right-drag = resize
        ];

        # Repeating locked binds — volume + brightness (work on lockscreen, repeat while held)
        bindel = [
          ", XF86AudioRaiseVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@   5%+"
          ", XF86AudioLowerVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@   5%-"
          ", XF86MonBrightnessUp,   exec, brightnessctl set 10%+"
          ", XF86MonBrightnessDown, exec, brightnessctl set 10%-"
        ];

        # Locked binds — mute + media player (work on lockscreen, no repeat)
        bindl = [
          ", XF86AudioMute,    exec, wpctl set-mute @DEFAULT_AUDIO_SINK@   toggle"
          ", XF86AudioMicMute, exec, mic-toggle"
          ", XF86AudioPlay,    exec, playerctl play-pause"
          ", XF86AudioPause,   exec, playerctl play-pause"
          ", XF86AudioNext,    exec, playerctl next"
          ", XF86AudioPrev,    exec, playerctl previous"
          "$mod, M,            exec, mic-toggle"
        ];

        # ── Layout ────────────────────────────────────────────────────────
        general = {
          gaps_in  = 5;
          gaps_out = 10;
          border_size = 2;
          # Catppuccin Macchiato: mauve → blue gradient for active window
          "col.active_border"   = "rgba(c6a0f6ff) rgba(8aadf4ff) 45deg";
          "col.inactive_border" = "rgba(494d64ff)";
          layout = "dwindle";
        };

        decoration = {
          rounding = 10;
          blur = {
            enabled  = true;
            size     = 5;
            passes   = 2;
            new_optimizations = true;
          };
          shadow = {
            enabled      = true;
            range        = 8;
            render_power = 3;
            color        = "rgba(1a1a2e99)";
          };
        };

        animations = {
          enabled = true;
          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
          animation = [
            "windows,    1, 7,  myBezier"
            "windowsOut, 1, 7,  default, popin 80%"
            "border,     1, 10, default"
            "fade,       1, 7,  default"
            "workspaces, 1, 6,  default"
          ];
        };

        dwindle = {
          pseudotile     = true;
          preserve_split = true;
        };

        input = {
          kb_layout  = "us";
          follow_mouse = 1;        # focus follows cursor
          sensitivity  = 0;        # -1.0 to 1.0; 0 = no accel modification
          touchpad.natural_scroll = true;
        };

        misc = {
          force_default_wallpaper = 0;  # disable Hyprland's default wallpaper
          disable_hyprland_logo   = true;
        };

      };
    };

    # waybar: configured via modules/programs/waybar/default.nix wrapper derivation.
    # Installed in home.packages in the host's home.nix.

    # rofi: configured via modules/programs/rofi/default.nix wrapper derivation.
    # Installed in home.packages in the host's home.nix.

    # ════════════════════════════════════════════════════════════════════════
    # DUNST — notification daemon
    # ════════════════════════════════════════════════════════════════════════
    services.dunst = {
      enable = true;
      settings = {
        global = {
          width          = 300;
          height         = 200;
          offset         = "10x50";
          origin         = "top-right";
          transparency   = 5;
          frame_width    = 2;
          frame_color    = "#c6a0f6";   # mauve
          corner_radius  = 10;
          font           = "JetBrainsMono Nerd Font 10";
          format         = "<b>%s</b>\n%b";
          sort           = "yes";
          word_wrap      = "yes";
          markup         = "full";
        };

        urgency_low = {
          background = "#24273a";
          foreground = "#cad3f5";
          timeout    = 5;
        };

        urgency_normal = {
          background = "#24273a";
          foreground = "#cad3f5";
          frame_color = "#8aadf4";    # blue
          timeout    = 10;
        };

        urgency_critical = {
          background = "#24273a";
          foreground = "#cad3f5";
          frame_color = "#ed8796";   # red
          timeout    = 0;             # 0 = stays until dismissed
        };
      };
    };

    # ════════════════════════════════════════════════════════════════════════
    # SWAYBG — wallpaper (launched via exec-once above)
    # ════════════════════════════════════════════════════════════════════════
    # No config needed — swaybg is a plain process. See exec-once above.

    # ════════════════════════════════════════════════════════════════════════
    # HYPRIDLE — idle management
    # ════════════════════════════════════════════════════════════════════════
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          after_sleep_cmd    = "niri msg action power-on-monitors";
          ignore_dbus_inhibit = false;
          # pidof check prevents stacking multiple hyprlock instances
          lock_cmd           = "pidof hyprlock || hyprlock";
        };

        listener = [
          {
            timeout    = 600;   # 5 min — lock screen
            on-timeout = "pidof hyprlock || hyprlock";
          }
          {
            timeout    = 630;   # 5.5 min — turn off display
            on-timeout = "niri msg action power-off-monitors";
            on-resume  = "niri msg action power-on-monitors";
          }
          ] ++ lib.optionals (!(osConfig.services.qemuGuest.enable or false)) [
          {
            timeout    = 900;   # 15 min — hybrid-sleep (RAM + swap, fast resume)
            on-timeout = "systemctl hybrid-sleep";
          }
        ];
      };
    };

    # ════════════════════════════════════════════════════════════════════════
    # HYPRLOCK — screen locker
    # ════════════════════════════════════════════════════════════════════════
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          disable_loading_bar = false;
          grace               = 5;       # seconds before lock is enforced
          hide_cursor         = true;
          no_fade_in          = false;
        };

        background = [
          {
            path         = "/home/robie/nixos-config/media/redwoods.png";
            blur_passes  = 3;
            blur_size    = 8;
            brightness   = 0.7;
          }
        ];

        label = [
          {
            monitor  = "";
            text     = "cmd[update:1000] date +\"%H:%M\"";
            color    = "rgba(cad3f5ff)";
            font_size = 64;
            font_family = "JetBrainsMono Nerd Font";
            position = "0, 200";
            halign   = "center";
            valign   = "center";
          }
        ];

        input-field = [
          {
            monitor          = "";
            size             = "200, 50";
            position         = "0, -80";
            dots_center      = true;
            fade_on_empty    = false;
            font_color       = "rgb(cad3f5)";
            inner_color      = "rgb(24273a)";
            outer_color      = "rgb(c6a0f6)";
            outline_thickness = 3;
            placeholder_text = "Password...";
            shadow_passes    = 2;
            halign           = "center";
            valign           = "center";
          }
        ];
      };
    };

    # foot: configured via modules/programs/foot/default.nix wrapper derivation.
    # Installed in home.packages in the host's home.nix.

    # fish: configured via modules/programs/fish/default.nix wrapper derivation.
    # Installed in home.packages in the host's home.nix.

    # ════════════════════════════════════════════════════════════════════════
    # GTK THEME
    # ════════════════════════════════════════════════════════════════════════
    gtk = {
      enable = true;

      theme = {
        name    = "Catppuccin-Macchiato-Standard-Mauve-Dark";
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
      gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    };

    # ════════════════════════════════════════════════════════════════════════
    # QT THEME
    # ════════════════════════════════════════════════════════════════════════
    qt = {
      enable = true;
      platformTheme.name = "gtk";   # Qt apps follow GTK theme
    };

    # ════════════════════════════════════════════════════════════════════════
    # ADDITIONAL PACKAGES
    # ════════════════════════════════════════════════════════════════════════
    home.packages = with pkgs; [
      wlr-which-key    # keybind cheatsheet popup (Super+/)
      swaybg           # wallpaper (launched via exec-once; also used by `wallpaper` function)
      wl-clipboard     # wl-copy / wl-paste (Wayland clipboard)
      grim             # screenshot tool (captures Wayland output)
      slurp            # interactive region selector (used with grim)
      pavucontrol      # PulseAudio/PipeWire GUI volume control
      nwg-look         # GTK settings GUI (apply theme changes live)
      brightnessctl    # screen brightness control
      playerctl        # media player control (play/pause/next/prev)

      # Mic mute toggle — F9 generates no OS events on this ASUS BIOS, so this
      # script is bound to Super+M instead. It mutes PipeWire and syncs the LED.
      # Mutes ALL sources so both the analog and digital mics are silenced together.
      (pkgs.writeShellScriptBin "mic-toggle" ''
        # Determine new state: 1=mute, 0=unmute (based on current default source)
        if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
          NEW=0
        else
          NEW=1
        fi

        # Apply to every audio source (IDs change each boot, so parse wpctl status)
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
    # WLR-WHICH-KEY — keybind cheatsheet popup (Super+/)
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

  };
}
