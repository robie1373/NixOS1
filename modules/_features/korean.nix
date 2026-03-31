{ pkgs, ... }:
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
          "Groups/0"        = { "Name" = "Default"; "Default Layout" = "us"; "DefaultIM" = "keyboard-us"; };
          "Groups/0/Items/0" = { "Name" = "keyboard-us"; "Layout" = ""; };
          "Groups/0/Items/1" = { "Name" = "hangul";      "Layout" = ""; };
          "GroupOrder"       = { "0" = "Default"; };
        };
        # Right Alt toggles EN ↔ Hangul (mirrors physical Korean keyboard convention)
        globalOptions = {
          "Hotkey" = { "TriggerKeys" = "Alt_R"; };
        };
      };
    };
  };

  # Required for GTK, Qt, and XWayland apps to route input through fcitx5
  environment.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE  = "fcitx";
    XMODIFIERS    = "@im=fcitx";
  };
}
