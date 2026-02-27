{ lib, config, pkgs, ... }:

{
  options.mySystem.desktopHyprland.enable =
    lib.mkEnableOption "Hyprland desktop";

  config = lib.mkIf config.mySystem.desktopHyprland.enable {

    # ── Compositor ──────────────────────────────────────────────────────────
    programs.hyprland.enable = true;

    # ── Shell ────────────────────────────────────────────────────────────────
    programs.fish.enable = true;

    # ── Display manager ──────────────────────────────────────────────────────
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd Hyprland";
          user = "greeter";
        };
      };
    };

    # ── Desktop portal ───────────────────────────────────────────────────────
    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-hyprland
        pkgs.xdg-desktop-portal-gtk      # needed for GTK file pickers
      ];
      config.common.default = "*";
    };

    # ── Screen locker PAM rule ───────────────────────────────────────────────
    security.pam.services.hyprlock = {};

    # ── Polkit ───────────────────────────────────────────────────────────────
    security.polkit.enable = true;

    # ── Fonts ─────────────────────────────────────────────────────────────────
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono    # glyphs used by Waybar and rofi
      noto-fonts
      noto-fonts-emoji
    ];

    # ── Wayland compatibility env vars ───────────────────────────────────────
    environment.sessionVariables = {
      NIXOS_OZONE_WL   = "1";            # Electron apps (VS Code, etc.)
      QT_QPA_PLATFORM  = "wayland";      # Qt apps
      MOZ_ENABLE_WAYLAND = "1";          # Firefox
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE    = "wayland";
    };

  };
}
