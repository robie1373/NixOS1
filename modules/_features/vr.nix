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

  # ── Monado — package only, no service units ───────────────────────────
  # services.monado.enable = true uses socket activation which starts Monado
  # regardless of wantedBy — it runs at login and claims Wayland input
  # resources, breaking Steam context menus. Confirmed on fivenix 2026-05-26.
  #
  # Package is installed directly. Start manually before VR, stop when done:
  #   monado-service &    # start
  #   kill %1             # stop (or pkill monado-service)
  environment.systemPackages = [ pkgs.monado ];

  # ── OpenComposite — OpenVR → OpenXR bridge ────────────────────────────
  # NOT system-wide — breaks Steam menus (intercepts Steam's internal OpenVR).
  # Per-game Steam launch option when ready to use:
  #   env PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/monado_comp_ipc %command%
}
