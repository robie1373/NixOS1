{ pkgs, ... }:
let
  # Niri output name for the HP Reverb G2 (from `niri msg outputs`).
  # Disabling it before Monado starts prevents niri from competing for the
  # DP-2 DRM lease, which would cause it to be withdrawn and the stereo
  # rendering to fall back to a broken non-direct path.
  g2OutputName = "HP Inc. 0x36C1 0x88272E62";

  niriBin = "${pkgs.niri}/bin/niri";

  niriG2Off = pkgs.writeShellScript "monado-pre" ''
    ${niriBin} msg output "${g2OutputName}" off || true
  '';

  niriG2On = pkgs.writeShellScript "monado-post" ''
    ${niriBin} msg output "${g2OutputName}" on || true
  '';
in
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
      # Forces G2 into NVIDIA's display allowlist for direct mode rendering.
      # DP-2 confirmed via /sys/class/drm (DP-1=monitor, DP-2=G2 at 2880x1440).
      XRT_COMPOSITOR_FORCE_NVIDIA_DISPLAY = "DP-2";
    };
    serviceConfig = {
      TimeoutStopSec = 5;  # default 90s causes long reboot delay
      # Disable the G2 niri output before Monado starts so niri doesn't compete
      # for the DP-2 DRM lease. Without this, niri grants the lease then immediately
      # withdraws it, causing Monado to fall back to a broken non-direct rendering
      # path (vertical stereo offset / double vision).
      ExecStartPre = "-${niriG2Off}";
      ExecStopPost = "-${niriG2On}";
    };
  };

  # ── Steam — OpenXR runtime visibility inside bubblewrap sandbox ──────
  # Steam runs games in an FHS bubblewrap container. Without this variable
  # it cannot see the Monado socket and ignores the OpenXR runtime entirely.
  # Using sessionVariables rather than programs.steam.package override —
  # the override approach broke Steam menus (see ledger2/tech/vr-nixos.md).
  environment.sessionVariables.PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";

  # ── OpenComposite — OpenVR → OpenXR bridge (Monado path) ─────────────
  # Intercepts Steam game OpenVR calls and routes them to Monado.
  # Installed but NOT registered as the active runtime — SteamVR manages
  # openvrpaths.vrpath itself. To switch to the Monado path, manually set:
  #   ~/.config/openvr/openvrpaths.vrpath → opencomposite store path
  # (previously done via tmpfiles L+ rule, removed 2026-06-01 to allow
  # Gamescope + SteamVR path to work — SteamVR can't override a forced symlink)
  environment.systemPackages = [ pkgs.opencomposite ];
}
