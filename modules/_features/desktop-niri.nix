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

  # ── wlr-which-key config ────────────────────────────────────────────────────
  # Written via user tmpfiles so the store path (with embedded selfpkgs paths) is
  # always current after a switch.
  systemd.user.tmpfiles.rules = [
    "L+ %h/.config/wlr-which-key/config.yaml - - - - ${pkgs.writeText "wlr-which-key-config.yaml" ''
      font: "JetBrainsMono Nerd Font 14"
      background: "#24273a"
      color: "#cad3f5"
      border: "#8aadf4"
      border_width: 2
      corner_r: 10
      padding: 20
      margin_top: 20
      margin_right: 20
      margin_bottom: 20
      margin_left: 20
      anchor: center

      menu:
        - key: Return
          desc: "terminal"
          cmd: "${selfpkgs.foot}/bin/foot"
        - key: d
          desc: "app launcher"
          cmd: "${selfpkgs.rofi}/bin/rofi -show drun"
        - key: e
          desc: "window switcher"
          cmd: "${selfpkgs.rofi}/bin/rofi -show window"
        - key: w
          desc: "windows →"
          submenu:
            - key: u
              desc: "close"
              cmd: "niri msg action close-window"
            - key: f
              desc: "fullscreen"
              cmd: "niri msg action fullscreen-window"
            - key: v
              desc: "float toggle"
              cmd: "niri msg action toggle-window-floating"
        - key: m
          desc: "media →"
          submenu:
            - key: u
              desc: "vol +"
              cmd: "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
              keep_open: true
            - key: d
              desc: "vol -"
              cmd: "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
              keep_open: true
            - key: m
              desc: "mute toggle"
              cmd: "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
            - key: p
              desc: "play/pause"
              cmd: "playerctl play-pause"
            - key: n
              desc: "next track"
              cmd: "playerctl next"
    ''}"
  ];

  # ── Session environment ─────────────────────────────────────────────────────
  environment.sessionVariables = {
    NIXOS_OZONE_WL      = "1";      # Electron apps (VS Code, etc.)
    QT_QPA_PLATFORM     = "wayland";
    MOZ_ENABLE_WAYLAND  = "1";
    XDG_CURRENT_DESKTOP = "niri";
    XDG_SESSION_TYPE    = "wayland";
  };
}
