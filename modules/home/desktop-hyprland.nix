{ lib, config, pkgs, ... }:

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

        monitor = "Virtual-1,1920x1200,0x0,1";

        # Programs launched once on startup
        exec-once = [
          "waybar"
          "dunst"
          "hyprpaper"
          "hypridle"
        ];

        # Modifier key: SUPER = the Windows/Command key
        "$mod" = "SUPER";

        # ── Keybinds ──────────────────────────────────────────────────────
        bind = [
          # Apps
          "$mod, Return, exec, ${pkgs.foot}/bin/foot"
          "$mod, D, exec, ${pkgs.rofi}/bin/rofi -show drun"
          "$mod, E, exec, ${pkgs.rofi}/bin/rofi -show window"

          # Window management
          "$mod, Q, killactive,"
          "$mod, M, exit,"
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
        ];

        # Mouse binds
        bindm = [
          "$mod, mouse:272, movewindow"    # SUPER + left-drag  = move
          "$mod, mouse:273, resizewindow"  # SUPER + right-drag = resize
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
          touchpad.natural_scroll = false;
        };

        misc = {
          force_default_wallpaper = 0;  # disable Hyprland's default wallpaper
          disable_hyprland_logo   = true;
        };

      };
    };

    # ════════════════════════════════════════════════════════════════════════
    # WAYBAR — status bar
    # ════════════════════════════════════════════════════════════════════════
    programs.waybar = {
      enable = true;

      settings = {
        mainBar = {
          layer    = "top";
          position = "top";
          height   = 32;

          modules-left   = [ "hyprland/workspaces" ];
          modules-center = [ "clock" ];
          modules-right  = [
            "pulseaudio" "network" "cpu" "memory" "tray"
          ];

          "hyprland/workspaces" = {
            disable-scroll = true;
            all-outputs    = true;
            format         = "{name}";
          };

          clock = {
            format     = " {:%H:%M}";
            format-alt = " {:%A, %B %d, %Y}";
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          };

          cpu = {
            format  = " {usage}%";
            tooltip = false;
          };

          memory = {
            format = " {used:.1f}G";
          };

          network = {
            format-wifi       = " {signalStrength}%";
            format-ethernet   = " connected";
            format-disconnected = "⚠ offline";
            tooltip-format-wifi = "{essid} ({signalStrength}%)";
          };

          pulseaudio = {
            format         = "{icon} {volume}%";
            format-muted   = " muted";
            format-icons   = { default = [ "" "" "" ]; };
            on-click       = "pavucontrol";
          };

          tray = {
            spacing = 8;
          };
        };
      };

      # Catppuccin Macchiato color palette
      style = ''
        @define-color base     #24273a;
        @define-color mantle   #1e2030;
        @define-color surface0 #363a4f;
        @define-color surface1 #494d64;
        @define-color text     #cad3f5;
        @define-color subtext1 #b8c0e0;
        @define-color mauve    #c6a0f6;
        @define-color blue     #8aadf4;
        @define-color green    #a6da95;
        @define-color red      #ed8796;
        @define-color yellow   #eed49f;
        @define-color peach    #f5a97f;

        * {
          font-family: "JetBrainsMono Nerd Font";
          font-size: 13px;
          min-height: 0;
        }

        window#waybar {
          background-color: @base;
          color: @text;
          border-bottom: 2px solid @mauve;
        }

        .modules-left,
        .modules-center,
        .modules-right {
          margin: 4px 8px;
        }

        #workspaces button {
          padding: 2px 8px;
          background-color: @surface0;
          color: @subtext1;
          border-radius: 6px;
          margin: 4px 2px;
          border: 1px solid transparent;
          transition: all 0.2s ease;
        }

        #workspaces button.active {
          background-color: @mauve;
          color: @base;
          font-weight: bold;
        }

        #workspaces button:hover {
          background-color: @surface1;
          color: @text;
        }

        #clock        { color: @blue;   padding: 0 10px; }
        #cpu          { color: @green;  padding: 0 8px;  }
        #memory       { color: @yellow; padding: 0 8px;  }
        #network      { color: @mauve;  padding: 0 8px;  }
        #pulseaudio   { color: @peach;  padding: 0 8px;  }
        #tray         { padding: 0 8px; }
      '';
    };

    # ════════════════════════════════════════════════════════════════════════
    # ROFI — app launcher
    # ════════════════════════════════════════════════════════════════════════

    # Place the Catppuccin Macchiato rofi theme file
    xdg.configFile."rofi/themes/catppuccin-macchiato.rasi".text = ''
      * {
        bg-col:          #24273a;
        bg-col-light:    #363a4f;
        border-col:      #24273a;
        selected-col:    #363a4f;
        blue:            #8aadf4;
        fg-col:          #cad3f5;
        fg-col2:         #ed8796;
        grey:            #6e738d;

        width:           600;
        font:            "JetBrainsMono Nerd Font 14";
      }

      element-text, element-icon, mode-switcher {
        background-color: inherit;
        text-color:       inherit;
      }

      window {
        height:           360px;
        border:           3px;
        border-color:     @border-col;
        background-color: @bg-col;
        border-radius:    12px;
      }

      mainbox {
        background-color: @bg-col;
      }

      inputbar {
        children:         [ prompt, entry ];
        background-color: @bg-col;
        border-radius:    5px;
        padding:          2px;
      }

      prompt {
        background-color: @blue;
        padding:          6px;
        text-color:       @bg-col;
        border-radius:    3px;
        margin:           20px 0 0 20px;
      }

      textbox-prompt-colon {
        expand:           false;
        str:              ":";
      }

      entry {
        padding:          6px;
        margin:           20px 0 0 10px;
        text-color:       @fg-col;
        background-color: @bg-col;
      }

      listview {
        border:           0 2px 0;
        padding:          6px 0 6px;
        margin:           10px 0 0 20px;
        columns:          2;
        lines:            5;
        background-color: @bg-col;
      }

      element {
        padding:          5px;
        background-color: @bg-col;
        text-color:       @fg-col;
      }

      element-icon {
        size:             25px;
      }

      element selected {
        background-color: @selected-col;
        text-color:       @fg-col2;
      }

      mode-switcher {
        spacing:          0;
      }

      button {
        padding:          10px;
        background-color: @bg-col-light;
        text-color:       @grey;
        vertical-align:   0.5;
        horizontal-align: 0.5;
      }

      button selected {
        background-color: @bg-col;
        text-color:       @fg-col;
      }

      message {
        background-color: @bg-col-light;
        margin:           2px;
        padding:          2px;
        border-radius:    5px;
      }

      textbox {
        padding:          6px;
        margin:           20px 0 0 20px;
        text-color:       @fg-col;
        background-color: @bg-col-light;
      }
    '';

    programs.rofi = {
      enable  = true;
      package = pkgs.rofi;
      terminal = "${pkgs.foot}/bin/foot";
      # "catppuccin-macchiato" matches the filename we placed above
      theme   = "catppuccin-macchiato";
      extraConfig = {
        modi        = "drun,run,window";
        show-icons  = true;
        icon-theme  = "Papirus-Dark";
        drun-display-format = "{name}";
        disable-history     = false;
      };
    };

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
    # HYPRPAPER — wallpaper
    # ════════════════════════════════════════════════════════════════════════
    services.hyprpaper = {
      enable = true;
      settings = {
        # preload caches the image at startup
        preload  = [ "/home/robie/nixos-config/media/ComicBookForest.png" ];
        # wallpaper format: "monitor,path"  (empty monitor = all monitors)
        wallpaper = [ ",/home/robie/nixos-config/media/ComicBookForest.png" ];
        splash    = false;
      };
    };

    # ════════════════════════════════════════════════════════════════════════
    # HYPRIDLE — idle management
    # ════════════════════════════════════════════════════════════════════════
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          after_sleep_cmd    = "hyprctl dispatch dpms on";
          ignore_dbus_inhibit = false;
          # pidof check prevents stacking multiple hyprlock instances
          lock_cmd           = "pidof hyprlock || hyprlock";
        };

        listener = [
          {
            timeout    = 300;   # 5 min — lock screen
            on-timeout = "pidof hyprlock || hyprlock";
          }
          {
            timeout    = 330;   # 5.5 min — turn off display
            on-timeout = "hyprctl dispatch dpms off";
            on-resume  = "hyprctl dispatch dpms on";
          }
          {
            timeout    = 600;   # 10 min — suspend
            on-timeout = "systemctl suspend";
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
          grace               = 0;       # seconds before lock is enforced
          hide_cursor         = true;
          no_fade_in          = false;
        };

        background = [
          {
            path         = "/home/robie/nixos-config/media/ComicBookForest.png";
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

    # ════════════════════════════════════════════════════════════════════════
    # FOOT — terminal
    # ════════════════════════════════════════════════════════════════════════
    programs.foot = {
      enable = true;
      settings = {
        main = {
          font       = "JetBrainsMono Nerd Font:size=12";
          pad        = "12x12";
        };

        scrollback = {
          lines = 5000;
        };

        colors = {
          # Catppuccin Macchiato palette (foot uses hex without #)
          foreground           = "cad3f5";
          background           = "24273a";
          selection-foreground = "cad3f5";
          selection-background = "363a4f";

          # Black
          regular0 = "494d64"; bright0 = "5b6078";
          # Red
          regular1 = "ed8796"; bright1 = "ed8796";
          # Green
          regular2 = "a6da95"; bright2 = "a6da95";
          # Yellow
          regular3 = "eed49f"; bright3 = "eed49f";
          # Blue
          regular4 = "8aadf4"; bright4 = "8aadf4";
          # Magenta / Mauve
          regular5 = "c6a0f6"; bright5 = "c6a0f6";
          # Cyan / Sky
          regular6 = "91d7e3"; bright6 = "91d7e3";
          # White
          regular7 = "b8c0e0"; bright7 = "a5adcb";
        };

        cursor = {
          color = "24273a f4dbd6";   # text background (rosewater cursor)
        };
      };
    };

    # ════════════════════════════════════════════════════════════════════════
    # FISH — shell
    # ════════════════════════════════════════════════════════════════════════
    programs.fish = {
      enable = true;

      interactiveShellInit = ''
        set fish_greeting ""   # silence the default welcome banner
      '';

      # Fish-specific aliases (these augment home.shellAliases from common.nix)
      shellAliases = {
        rebuild = "sudo nixos-rebuild switch --flake /home/robie/nixos-config#nixos1";
        build   = "nixos-rebuild build --flake /home/robie/nixos-config#nixos1";
      };
    };

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
      wl-clipboard     # wl-copy / wl-paste (Wayland clipboard)
      grim             # screenshot tool (captures Wayland output)
      slurp            # interactive region selector (used with grim)
      pavucontrol      # PulseAudio/PipeWire GUI volume control
      nwg-look         # GTK settings GUI (apply theme changes live)
      brightnessctl    # screen brightness control
    ];

  };
}
