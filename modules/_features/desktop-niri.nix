{ pkgs, self, ... }:
let
  selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
in {
  # Install wrapped niri (includes filesToPatch'd niri.service pointing at the wrapper).
  # systemd.packages makes the user service visible to `systemctl --user`.
  environment.systemPackages = [
    selfpkgs.niri pkgs.xwayland-satellite
    # Wrapped desktop apps (nix-wrapper-modules — config baked in)
    selfpkgs.zathura selfpkgs.foot selfpkgs.rofi selfpkgs.waybar selfpkgs.okular
  ];
  systemd.packages = [
    selfpkgs.niri
    # poweralertd ships a user service file; wantedBy wires it to the graphical session.
    pkgs.poweralertd
  ];
  systemd.user.services.poweralertd.wantedBy = [ "graphical-session.target" ];

  # fish is also enabled in common.nix; both setting it true is idempotent
  programs.fish.enable = true;

  # dconf: required for HM's dconfSettings activation step (GTK settings, etc.)
  # programs.hyprland.enable pulled this in transitively; with niri we set it explicitly.
  programs.dconf.enable = true;

  # ── Display manager ─────────────────────────────────────────────────────────
  # greetd is enabled by programs.regreet in greeter-regreet.nix.
  # Enabling it here too is idempotent; the PAM entry is what we need.
  services.greetd.enable = true;

  # ── Desktop portal ──────────────────────────────────────────────────────────
  # niri uses xdg-desktop-portal-gnome for screencasting (via the xdp-gnome-screencast
  # build feature). gtk portal handles file pickers and other fallback requests.
  xdg.portal = {
    enable       = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common.default = "*";
  };

  # ── Bluetooth ───────────────────────────────────────────────────────────────
  services.blueman.enable = true;

  # ── PAM ─────────────────────────────────────────────────────────────────────
  # Unlock gnome-keyring at greetd login so 1Password CLI + SSH agents survive reboots.
  security.pam.services.greetd.enableGnomeKeyring = true;

  # ── Polkit ──────────────────────────────────────────────────────────────────
  security.polkit.enable = true;

  # ── Fonts ───────────────────────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # ── Backlight ───────────────────────────────────────────────────────────────
  services.udev.packages = [ pkgs.brightnessctl ];

  # ── Session environment ─────────────────────────────────────────────────────
  environment.sessionVariables = {
    NIXOS_OZONE_WL      = "1";      # Electron apps (VS Code, etc.)
    QT_QPA_PLATFORM     = "wayland";
    MOZ_ENABLE_WAYLAND  = "1";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_TYPE    = "wayland";
  };
}
