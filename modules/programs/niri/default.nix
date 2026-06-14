{ inputs, self, ... }:
# Niri compositor — configured via nix-wrapper-modules (bakes config into the binary).
# NIRI_CONFIG env var is set to the generated KDL store path; no ~/.config/niri needed.
{
  perSystem = { pkgs, ... }:
    let
      selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    in {
      packages.niri = inputs.nix-wrapper-modules.wrappers.niri.wrap {
        inherit pkgs;
        v2-settings = true;

        settings = {
          "prefer-no-csd" = _: {};

          hotkey-overlay."skip-at-startup" = _: {};

          input = {
            keyboard.xkb.layout = "us";
            touchpad = {
              "natural-scroll" = _: {};
              tap = _: {};
            };
          };

          layout = {
            gaps = 8;
            "focus-ring" = {
              width = 2;
              "active-color"   = "#c6a0f6";  # Catppuccin Macchiato mauve
              "inactive-color" = "#494d64";  # Catppuccin Macchiato surface1
            };
          };

          # Noctalia handles bar, notifications, lock, wallpaper, and launcher.
          # Swaybg and waybar are no longer needed as separate spawns.
          spawn-at-startup = [
            # noctalia v5 renamed the binary noctalia-shell -> noctalia (2026-06-14)
            "${selfpkgs.noctalia}/bin/noctalia"
          ];

          # xwayland-satellite: niri manages the X11 socket and restarts this process
          # on crash. niri's built-in integration (>= v0.2) is used rather than spawn-at-startup.
          extraConfig = ''
            xwayland-satellite {
              path "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
            }
          '';

          binds = {
            # IME toggle — bind at compositor level; fcitx5 never sees Alt_R via Wayland IM protocol
            "Alt_R".spawn = [ "${pkgs.fcitx5}/bin/fcitx5-remote" "-t" ];

            # Apps
            "Mod+Return".spawn = [ "${selfpkgs.foot}/bin/foot" ];
            "Mod+D".spawn      = [ "${selfpkgs.rofi}/bin/rofi" "-show" "drun" ];
            "Mod+E".spawn      = [ "${selfpkgs.rofi}/bin/rofi" "-show" "window" ];

            # Window management
            "Mod+U".close-window           = _: {};
            "Mod+F".fullscreen-window      = _: {};
            "Mod+V".toggle-window-floating = _: {};

            # Focus — vim-style column/window navigation
            "Mod+H".focus-column-left  = _: {};
            "Mod+L".focus-column-right = _: {};
            "Mod+K".focus-window-up    = _: {};
            "Mod+J".focus-window-down  = _: {};

            # Move windows
            "Mod+Shift+H".move-column-left  = _: {};
            "Mod+Shift+L".move-column-right = _: {};
            "Mod+Shift+K".move-window-up    = _: {};
            "Mod+Shift+J".move-window-down  = _: {};

            # Workspaces 1–5
            "Mod+1".focus-workspace = 1;
            "Mod+2".focus-workspace = 2;
            "Mod+3".focus-workspace = 3;
            "Mod+4".focus-workspace = 4;
            "Mod+5".focus-workspace = 5;

            "Mod+Shift+1".move-window-to-workspace = 1;
            "Mod+Shift+2".move-window-to-workspace = 2;
            "Mod+Shift+3".move-window-to-workspace = 3;
            "Mod+Shift+4".move-window-to-workspace = 4;
            "Mod+Shift+5".move-window-to-workspace = 5;

            # Screenshot — region select, copy to clipboard
            "Print".spawn-sh = ''${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy'';

            # Keybind cheatsheet popup
            "Mod+Slash".spawn = [ "${pkgs.wlr-which-key}/bin/wlr-which-key" ];

            # Bearing session in a foot terminal
            "Mod+B".spawn = [ "${selfpkgs.foot}/bin/foot" "--" "bash" "-c" "cd ~/work && claude bearing; exec bash" ];

            # Elite Dangerous: request docking (fivenix only — no-op on other hosts)
            # Compositor handles this hotkey without stealing focus from ED; ydotool
            # injects the key sequence into the currently-focused window (ED).
            "Mod+G".spawn-sh = "ed-request-docking";

            # Volume — allow-when-locked so keys work on the lock screen
            "XF86AudioRaiseVolume" = _: { props."allow-when-locked" = true; content."spawn-sh" = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"; };
            "XF86AudioLowerVolume" = _: { props."allow-when-locked" = true; content."spawn-sh" = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"; };
            "XF86AudioMute"        = _: { props."allow-when-locked" = true; content."spawn-sh" = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; };
            "XF86AudioMicMute"     = _: { props."allow-when-locked" = true; content."spawn-sh" = "mic-toggle"; };

            # Brightness — allow-when-locked
            "XF86MonBrightnessUp"   = _: { props."allow-when-locked" = true; content."spawn-sh" = "brightnessctl set 10%+"; };
            "XF86MonBrightnessDown" = _: { props."allow-when-locked" = true; content."spawn-sh" = "brightnessctl set 10%-"; };

            # Media — allow-when-locked
            "XF86AudioPlay"  = _: { props."allow-when-locked" = true; content."spawn-sh" = "playerctl play-pause"; };
            "XF86AudioPause" = _: { props."allow-when-locked" = true; content."spawn-sh" = "playerctl play-pause"; };
            "XF86AudioNext"  = _: { props."allow-when-locked" = true; content."spawn-sh" = "playerctl next"; };
            "XF86AudioPrev"  = _: { props."allow-when-locked" = true; content."spawn-sh" = "playerctl previous"; };

            # Mic toggle — Super+M since F9 generates no OS events on this ASUS BIOS
            "Mod+M" = _: { props."allow-when-locked" = true; content."spawn-sh" = "mic-toggle"; };
          };
        };
      };
    };
}
