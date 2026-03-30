{ pkgs, ... }:
{
  # ── Compositor ──────────────────────────────────────────────────────────
  programs.hyprland.enable = true;

  # fish is also enabled in common.nix; both setting it true is fine
  programs.fish.enable = true;

  # ── Display manager ──────────────────────────────────────────────────────
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd start-hyprland";
      user    = "greeter";
    };
  };

  # ── Desktop portal ───────────────────────────────────────────────────────
  xdg.portal = {
    enable       = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk   # needed for GTK file pickers
    ];
    config.common.default = "*";
  };

  # ── Bluetooth ────────────────────────────────────────────────────────────
  services.blueman.enable = true;

  # ── Screen locker PAM rule ───────────────────────────────────────────────
  security.pam.services.hyprlock = {};

  # ── Keyring unlock at login ───────────────────────────────────────────────
  # Unlocks gnome-keyring automatically when greetd authenticates the user,
  # so 1Password CLI and SSH agent sessions survive across reboots.
  security.pam.services.greetd.enableGnomeKeyring = true;

  # ── Polkit ───────────────────────────────────────────────────────────────
  security.polkit.enable = true;

  # ── Fonts ─────────────────────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono   # glyphs used by Waybar and rofi
    noto-fonts
    noto-fonts-color-emoji
  ];

  # ── Backlight udev rules (allows video group to write brightness) ─────────
  services.udev.packages = [ pkgs.brightnessctl ];

  # ── Wayland compatibility env vars ───────────────────────────────────────
  environment.sessionVariables = {
    NIXOS_OZONE_WL      = "1";        # Electron apps (VS Code, etc.)
    QT_QPA_PLATFORM     = "wayland";  # Qt apps
    MOZ_ENABLE_WAYLAND  = "1";        # Firefox
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE    = "wayland";
  };
}
