{ pkgs, config, ... }:
{
  i18n.inputMethod = {
    enable = true;
    type   = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-hangul   # Korean IM
        fcitx5-gtk      # GTK2/3/4 IM module
      ];
      settings = {
        # Input method list: US keyboard + Hangul
        inputMethod = {
          "Groups/0"         = { "Name" = "Default"; "Default Layout" = "us"; "DefaultIM" = "keyboard-us"; };
          "Groups/0/Items/0" = { "Name" = "keyboard-us"; "Layout" = ""; };
          "Groups/0/Items/1" = { "Name" = "hangul";      "Layout" = ""; };
          "GroupOrder"       = { "0" = "Default"; };
        };
        # Right Alt (Alt_R) toggles EN ↔ Hangul.
        # This is the standard key on physical Korean keyboards.
        # Caps_Lock as trigger does not work on Wayland — the compositor consumes it
        # as a modifier before it reaches fcitx5. Alt_R is a regular keypress and
        # survives the Wayland input stack reliably.
        globalOptions = {
          "Hotkey" = { "TriggerKeys" = "Alt_R"; };
        };
      };
    };
  };

  # Start fcitx5 via systemd user service.
  # i18n.inputMethod creates an XDG autostart .desktop file, but Hyprland does not
  # process XDG autostart entries. A systemd user service is required instead.
  systemd.user.services.fcitx5 = {
    description = "Fcitx5 input method daemon";
    partOf      = [ "graphical-session.target" ];
    wantedBy    = [ "graphical-session.target" ];
    after       = [ "graphical-session.target" ];
    serviceConfig = {
      Type       = "simple";
      ExecStart  = "${config.i18n.inputMethod.package}/bin/fcitx5 --replace";
      Restart    = "on-failure";
      RestartSec = 1;
    };
  };

  # fcitx5 Wayland mode: do NOT set GTK_IM_MODULE — GTK4 and Wayland-native apps
  # use the Wayland text-input protocol directly. Setting GTK_IM_MODULE conflicts
  # with the Wayland IM frontend. XMODIFIERS covers XWayland apps.
  # QT_IM_MODULE retained for Qt5 apps that don't use the Wayland IM protocol natively.
  environment.sessionVariables = {
    QT_IM_MODULE = "fcitx";
    XMODIFIERS   = "@im=fcitx";
  };
}
