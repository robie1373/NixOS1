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
        # No TriggerKeys — toggle is handled by a niri keybind calling fcitx5-remote -t.
        # fcitx5 cannot intercept modifier keys (Alt_R) on Wayland via the IM protocol;
        # the compositor must do it at the keyboard event level instead.
        globalOptions = {
          "Hotkey" = { "TriggerKeys" = ""; };
        };
      };
    };
  };

  # Start fcitx5 via systemd user service.
  # i18n.inputMethod creates an XDG autostart .desktop file, but niri does not
  # process XDG autostart entries either. A systemd user service is required.
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
