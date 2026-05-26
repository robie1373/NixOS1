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

  # ── Monado — service + WMR config, no runtime registration ───────────
  # forceDefaultRuntime excluded — runtime selection handled separately
  # (step 3). This step tests whether the service alone affects Steam.
  #
  # Start/stop manually when doing VR:
  #   systemctl --user start monado
  #   systemctl --user stop monado
  services.monado = {
    enable = true;
    highPriority = true;
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

  # ── OpenComposite — pending step 4 ───────────────────────────────────
  # Per-game Steam launch option (once OpenComposite is wired up):
  #   env PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/monado_comp_ipc %command%
}
