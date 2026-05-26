{ pkgs, ... }:
{
  # ── USB device access ─────────────────────────────────────────────────
  # HP Reverb G2 uses Microsoft USB vendor ID (045e).
  # TAG+="uaccess" gives the logged-in seat user access without needing
  # a dedicated group — replaces what SteamVR tries to do as superuser.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb",    ATTRS{idVendor}=="045e", TAG+="uaccess"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="045e", TAG+="uaccess"
  '';

  # ── Monado — service with runtime registration ───────────────────────
  # forceDefaultRuntime writes ~/.config/openxr/1/active_runtime.json only
  # while the service is running — safe, does not affect Steam at rest.
  # (contrast: defaultRuntime=true writes permanently and broke Steam menus)
  #
  # Start/stop manually when doing VR:
  #   systemctl --user start monado
  #   systemctl --user stop monado
  services.monado = {
    enable = true;
    highPriority = true;
    forceDefaultRuntime = true;
  };

  systemd.user.services.monado = {
    environment = {
      WMR_HANDTRACKING = "0";
      U_PACING_APP_USE_MIN_FRAME_PERIOD = "1";
      U_PACING_COMP_MIN_TIME_MS = "5";
      # NVIDIA: uncomment and set to display name from xrandr if headset not detected:
      # XRT_COMPOSITOR_FORCE_NVIDIA_DISPLAY = "";
    };
    serviceConfig.TimeoutStopSec = 5;  # default 90s causes long reboot delay
  };

  # ── Steam — OpenXR runtime visibility inside bubblewrap sandbox ──────
  # Steam runs games in an FHS bubblewrap container. Without this variable
  # it cannot see the Monado socket and ignores the OpenXR runtime entirely.
  # Using sessionVariables rather than programs.steam.package override —
  # the override approach broke Steam menus (see ledger2/tech/vr-nixos.md).
  environment.sessionVariables.PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";

  # ── OpenComposite — OpenVR → OpenXR bridge ────────────────────────────
  # Intercepts Steam game OpenVR calls and routes them to Monado.
  # openvrpaths.vrpath is written as a symlink via tmpfiles so it tracks
  # the opencomposite store path across version updates automatically.
  environment.systemPackages = [ pkgs.opencomposite ];

  systemd.user.tmpfiles.rules =
    let
      vrpaths = pkgs.writeText "openvrpaths.vrpath" (builtins.toJSON {
        config           = [];
        external_drivers = null;
        jsonid           = "vrpathreg";
        log              = [];
        runtime          = [ "${pkgs.opencomposite}/lib/opencomposite" ];
        version          = 1;
      });
    in [
      "L+ %h/.config/openvr/openvrpaths.vrpath - - - - ${vrpaths}"
    ];

  # ── Per-game Steam launch option ─────────────────────────────────────
  # Add to ED's launch options in Steam so the game can reach the Monado
  # socket inside Steam's bubblewrap container:
  #   env PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/monado_comp_ipc %command%
}
