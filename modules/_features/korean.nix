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
        # Caps Lock toggles EN ↔ Hangul directly.
        # fcitx5 intercepts the Caps_Lock keysym before the OS processes it —
        # no xkb remapping required. Caps Lock typing functionality is lost (intended).
        globalOptions = {
          "Hotkey" = { "TriggerKeys" = "Caps_Lock"; };
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
      ExecStart  = "${config.i18n.inputMethod.package}/bin/fcitx5 --replace -d";
      Restart    = "on-failure";
      RestartSec = 1;
    };
  };

  # Required for GTK, Qt, and XWayland apps to route input through fcitx5
  environment.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE  = "fcitx";
    XMODIFIERS    = "@im=fcitx";
  };
}
