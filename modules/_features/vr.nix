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

  # ── Monado — OpenXR runtime with WMR driver ───────────────────────────
  services.monado = {
    enable = true;
    defaultRuntime = true;  # sets system-wide OPENXR_RUNTIME_FILE
    highPriority = true;    # real-time scheduling for the compositor
  };

  # Monado environment tuning for WMR headsets
  systemd.user.services.monado.environment = {
    WMR_HANDTRACKING = "0";                  # skip: needs external model files
    U_PACING_APP_USE_MIN_FRAME_PERIOD = "1"; # reduces frame pacing issues
    U_PACING_COMP_MIN_TIME_MS = "5";         # reduces headset view stuttering

    # NVIDIA: if Monado fails to detect the headset display, uncomment and set
    # to the display name from `xrandr` (e.g. "DP-1" or "HDMI-0"):
    # XRT_COMPOSITOR_FORCE_NVIDIA_DISPLAY = "";
  };

  # ── Steam — OpenXR visibility inside bubblewrap sandbox ───────────────
  # NOTE: programs.steam.package override removed — broke Steam right-click
  # context menus. PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 needs a
  # different delivery mechanism (per-game launch option or environment.d).

  # ── OpenComposite — OpenVR → OpenXR bridge ────────────────────────────
  # NOTE: NOT installed system-wide. Installing opencomposite globally intercepts
  # Steam's own internal OpenVR use and breaks right-click context menus.
  # Install per-user via nix profile or add to a game-specific wrapper instead.
  #
  # Per-game Steam launch option when using opencomposite:
  #   env PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/monado_comp_ipc %command%
}
