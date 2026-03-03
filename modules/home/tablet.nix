{ lib, config, pkgs, ... }:

{
  options.myHome.tablet.enable =
    lib.mkEnableOption "tablet mode workaround (rotate + disable kbd/touchpad + waybar toggle)";

  config = lib.mkIf config.myHome.tablet.enable {

    # ── Hyprland keybind ─────────────────────────────────────────────────
    # Use extraConfig so this doesn't conflict with the list in desktop-hyprland.
    wayland.windowManager.hyprland.extraConfig = ''
      # Keyboard shortcut to enter tablet mode (while keyboard is still active)
      bind = $mod, T, exec, tablet-enter
    '';

    # ── Scripts ───────────────────────────────────────────────────────────
    home.packages = [

      # Enter tablet mode:
      #   1. Rotate eDP-1 to portrait (transform 1 = 90° clockwise)
      #   2. Rotate touch input coordinates to match
      #   3. Disable keyboard, touchpad, power/sleep buttons via dispatch
      #      (dispatch handles colons in device names; keyword device:NAME: does not)
      #   4. Poke waybar to refresh the custom/tablet module
      (pkgs.writeShellApplication {
        name = "tablet-enter";
        runtimeInputs = [ ];
        text = ''
          STATE="/tmp/tablet-mode-devices"
          [[ -f "$STATE" ]] && { echo "already in tablet mode" >&2; exit 1; }

          hyprctl keyword monitor eDP-1,preferred,auto,1,transform,1
          hyprctl keyword input:touchdevice:transform 1

          # Devices confirmed via `hyprctl devices -j` on flipper.
          # intel-hid-5-button-array, asus-wmi-hotkeys, and BT left enabled.
          DEVICES=(
            "at-translated-set-2-keyboard"
            "ascp1205:00-093a:3020-touchpad"
            "ascp1205:00-093a:3020-mouse"
            "power-button"
            "sleep-button"
          )
          printf '%s\n' "''${DEVICES[@]}" > "$STATE"

          for dev in "''${DEVICES[@]}"; do
            hyprctl dispatch disabledevice "$dev"
          done

          pkill -RTMIN+8 waybar
        '';
      })

      # Exit tablet mode:
      #   1. Reset touch input rotation
      #   2. Re-enable all disabled devices
      #   3. Restore landscape orientation
      #   4. Poke waybar to refresh the custom/tablet module
      (pkgs.writeShellApplication {
        name = "tablet-exit";
        runtimeInputs = [ ];
        text = ''
          STATE="/tmp/tablet-mode-devices"

          hyprctl keyword input:touchdevice:transform 0

          if [[ -f "$STATE" ]]; then
            while IFS= read -r dev; do
              hyprctl dispatch enabledevice "$dev"
            done < "$STATE"
            rm -f "$STATE"
          fi

          hyprctl keyword monitor eDP-1,preferred,auto,1,transform,0

          pkill -RTMIN+8 waybar
        '';
      })
    ];

  };
}
