{ inputs, ... }:
# Waybar status bar — wrapped with Catppuccin Macchiato theme.
# settings serialises to waybar's JSON config; "style.css" holds the CSS.
#
# Tablet module (custom/tablet) is always present — its exec outputs nothing
# on hosts without tablet scripts, so the module is invisible there.
{
  perSystem = { pkgs, lib, ... }: {
    packages.waybar = inputs.nix-wrapper-modules.wrappers.waybar.wrap {
      inherit pkgs;

      settings = {
        layer    = "top";
        position = "top";
        height   = 32;

        modules-left   = [ "hyprland/workspaces" ];
        modules-center = [ "clock" ];
        modules-right  = [
          "battery" "backlight" "pulseaudio" "network" "cpu"
          "temperature" "memory" "bluetooth"
          "custom/iphone" "custom/tablet" "tray" "custom/power"
        ];

        "hyprland/workspaces" = {
          disable-scroll = true;
          all-outputs    = true;
          format         = "{name}";
        };

        battery = {
          states = { warning = 20; critical = 10; };
          format           = "󰁹 {capacity}%";
          format-charging  = "󰂄 {capacity}%";
          format-plugged   = "󰚥 {capacity}%";
          format-full      = "󰁹 {capacity}%";
          tooltip-format   = "{timeTo} · {power:.1f}W";
        };

        backlight = {
          format         = "󰃟 {percent}%";
          on-scroll-up   = "brightnessctl set 1%+";
          on-scroll-down = "brightnessctl set 1%-";
        };

        temperature = {
          critical-threshold = 80;
          # hwmon7 = coretemp on flipper. Verify with:
          # for f in /sys/class/hwmon/hwmon*/name; do echo "$f: $(cat $f)"; done
          hwmon-path      = "/sys/class/hwmon/hwmon7/temp1_input";
          format          = " {temperatureC}°C";
          format-critical = "󰸁 {temperatureC}°C";
        };

        clock = {
          format         = " {:%a, %H:%M}";
          format-alt     = " {:%A, %B %d, %Y}";
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        };

        cpu = {
          format  = " CPU:{usage}%";
          tooltip = false;
        };

        memory = {
          format = " {used:.1f}G";
        };

        network = {
          format-wifi         = " {essid} {signalStrength}%";
          format-ethernet     = " connected";
          format-disconnected = "⚠ offline";
          tooltip-format-wifi = "{essid} · {signalStrength}% · {ipaddr}";
          on-click            = "foot -e nmtui";
        };

        pulseaudio = {
          format         = "󰕾 {volume}%";
          format-muted   = "󰖁 muted";
          on-click       = "pavucontrol";
          on-scroll-up   = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+";
          on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-";
        };

        bluetooth = {
          format                                   = "󰂯 {status}";
          format-connected                         = "󰂱 {device_alias}";
          format-connected-battery                 = "󰂱 {device_alias} {device_battery_percentage}%";
          tooltip-format                           = "{controller_alias}\t{controller_address}";
          tooltip-format-connected                 = "{controller_alias}\n\n{num_connections} connected\n{device_enumerate}";
          tooltip-format-enumerate-connected       = "  {device_alias}";
          tooltip-format-enumerate-connected-battery = " {device_alias}\t{device_battery_percentage}%";
          on-click                                 = "blueman-manager";
        };

        tray = {
          spacing = 8;
        };

        "custom/power" = {
          format   = "⏻";
          tooltip  = false;
          on-click = "${pkgs.writeShellScript "waybar-power-menu" ''
            chosen=$(printf 'Lock\nSuspend\nHybrid Sleep\nHibernate\nReboot\nShutdown' | \
              rofi -dmenu -p "⏻ Power")
            case "$chosen" in
              "Lock")         pidof hyprlock || hyprlock ;;
              "Suspend")      systemctl suspend ;;
              "Hybrid Sleep") systemctl hybrid-sleep ;;
              "Hibernate")    systemctl hibernate ;;
              "Reboot")       systemctl reboot ;;
              "Shutdown")     systemctl poweroff ;;
            esac
          ''}";
        };

        # iPhone mount status — visible only when iPhone is mounted.
        "custom/iphone" = {
          return-type = "json";
          interval    = 2;
          exec = "${pkgs.writeShellScript "waybar-iphone-status" ''
            icon=$'\uf179'
            if ${pkgs.util-linux}/bin/mountpoint -q "$HOME/mnt/iphone" 2>/dev/null; then
              printf '{"text":"%s","class":"mounted","tooltip":"iPhone mounted · click to unmount"}\n' "$icon"
            else
              printf '{"text":"%s","class":""}\n' "$icon"
            fi
          ''}";
          on-click = "${pkgs.writeShellScript "waybar-iphone-unmount" ''
            /run/wrappers/bin/fusermount -u "$HOME/mnt/iphone"
          ''}";
        };

        # Tablet mode toggle. exec outputs nothing on non-tablet hosts so the
        # module remains invisible. Signal 8 lets Hyprland refresh it on demand.
        "custom/tablet" = {
          return-type = "json";
          exec = "${pkgs.writeShellScript "waybar-tablet-status" ''
            if test -f /tmp/tablet-mode-devices; then
              printf '{"text":"󰦟","class":"active","tooltip":"Exit tablet mode"}\n'
            else
              printf '{"text":"󰌌","class":"","tooltip":"Enter tablet mode (Super+T)"}\n'
            fi
          ''}";
          on-click = "${pkgs.writeShellScript "waybar-tablet-toggle" ''
            if test -f /tmp/tablet-mode-devices; then
              tablet-exit
            else
              tablet-enter
            fi
          ''}";
          interval = "once";
          signal   = 8;
        };
      };

      "style.css" = {
        content = ''
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
          @define-color ivory    #f5f0e0;

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
          #bluetooth           { color: @blue;    padding: 0 8px; }
          #bluetooth.connected { color: @green; }
          #bluetooth.disabled  { color: @surface1; }
          #tray         { padding: 0 8px; }

          #battery                { color: @green;  padding: 0 8px; }
          #battery.warning        { color: @yellow; }
          #battery.critical       { color: @red;
                                    animation-name:            blink;
                                    animation-duration:        0.5s;
                                    animation-timing-function: steps(1);
                                    animation-iteration-count: infinite;
                                    animation-direction:       alternate; }
          #battery.charging       { color: @blue; }
          #battery.plugged        { color: @blue; }

          #backlight    { color: @yellow; padding: 0 8px; }

          #temperature           { color: @green; padding: 0 8px; }
          #temperature.critical  { color: @red; }

          #custom-iphone         { padding: 0; font-size: 15px; }
          #custom-iphone.mounted { color: @ivory; padding: 0 8px; }

          #custom-power  { color: @red; padding: 0 12px; font-size: 15px; }

          #custom-tablet        { color: @blue;  padding: 0 8px; }
          #custom-tablet.active { color: @peach; }
        '';
      };
    };
  };
}
