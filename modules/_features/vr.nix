{ lib, pkgs, ... }:
{
  # ── USB device access ─────────────────────────────────────────────────
  # HP Reverb G2 uses Microsoft USB vendor ID (045e).
  # TAG+="uaccess" gives the logged-in seat user access without needing
  # a dedicated group — replaces what SteamVR tries to do as superuser.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb",    ATTRS{idVendor}=="045e", TAG+="uaccess"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="045e", TAG+="uaccess"
  '';

  # ── Monado — installed but NOT autostarted ────────────────────────────
  # services.monado.enable = true autostarts monado.service at login. Monado
  # claims Wayland input resources on startup, causing Steam popup/context
  # menus to require a text-box click to unstick (focus not established until
  # keyboard input occurs). Confirmed on fivenix 2026-05-26.
  #
  # Instead: install the package and provide env config, start on demand:
  #   systemctl --user start monado    # before launching a VR game
  #   systemctl --user stop monado     # when done
  #
  # The service unit and environment are still defined via services.monado
  # so the config is available; it just won't autostart.
  services.monado = {
    enable = true;
    forceDefaultRuntime = true;
    highPriority = true;
  };

  systemd.user.services.monado = {
    wantedBy = lib.mkForce [];  # remove from default.target — no autostart
    environment = {
      WMR_HANDTRACKING = "0";
      U_PACING_APP_USE_MIN_FRAME_PERIOD = "1";
      U_PACING_COMP_MIN_TIME_MS = "5";
      # NVIDIA: uncomment and set to display name from xrandr if headset not detected:
      # XRT_COMPOSITOR_FORCE_NVIDIA_DISPLAY = "";
    };
  };

  # ── OpenComposite — OpenVR → OpenXR bridge ────────────────────────────
  # NOT system-wide — breaks Steam menus (intercepts Steam's internal OpenVR).
  # Start monado first, then launch VR game with this Steam launch option:
  #   env PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/monado_comp_ipc %command%
}
