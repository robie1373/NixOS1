# Flipper convertible / tablet mode (niri).
#
# Flipper (ASUS Vivobook 14 Flip TP3407SA) folds into a portrait tablet. There is
# no working accelerometer under Linux — the Intel ISH firmware for this ASUS SKU
# has not been upstreamed (see ledger flipper.md / flipper-tablet.md) — so there
# is no automatic rotation or fold detection. This is a *manual* toggle.
#
# Design notes (why it works where the Hyprland-era version didn't):
#   * Rotation uses `niri msg output … transform` (runtime, temporary). niri 26.04
#     has no `set-output-transform` action; this subcommand is the replacement.
#   * Keyboard + touchpad are disabled with an exclusive evdev grab (evtest --grab),
#     NOT `hyprctl dispatch disabledevice` (a no-op under niri). robie is in the
#     `input` group, so the grab needs no root. The touchscreen + stylus (ILIT2901)
#     are deliberately left live as the primary escape hatch.
#   * NEVER-STUCK GUARANTEE: the on-screen exit button is launched and verified
#     BEFORE any input is disabled. If it fails to start, the script aborts with the
#     keyboard/touchpad still working. The exit trigger is touch-only (a floating yad
#     button) — it is never bound to the keyboard it just disabled.
#
# Entry: Mod+Shift+T (bound in modules/programs/niri/default.nix), run while the
# keyboard still works. Exit: touch the on-screen button, or `tablet-mode-off` over SSH.
{ pkgs, ... }:
let
  # Kernel input device names (compositor-independent; from /sys/class/input/*/device/name).
  # Confirmed on flipper 2026-06-30. Verify with the same path after a kernel bump.
  keyboardName = "AT Translated Set 2 keyboard";
  touchpadName = "ASCP1205:00 093A:3020 Touchpad";

  # Portrait transform. niri "90" matches the Hyprland-era transform 1 (90°).
  # If the screen rotates the wrong way for how you hold it, change to "270".
  portraitTransform = "90";

  baseInputs = with pkgs; [ niri coreutils procps libnotify ];

  tablet-mode-off = pkgs.writeShellApplication {
    name = "tablet-mode-off";
    runtimeInputs = baseInputs;
    text = ''
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/tablet-mode"
      # Idempotent: if we're not in tablet mode, do nothing. This makes it safe to
      # call from the exit-button watcher, the toggle, and SSH all at once.
      [ -d "$STATE" ] || exit 0

      # Re-enable keyboard + touchpad: killing the grab holders closes their fds,
      # which releases EVIOCGRAB.
      if [ -f "$STATE/grab.pids" ]; then
        while read -r pid; do
          [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
        done < "$STATE/grab.pids"
      fi

      # Stop the on-screen keyboard.
      if [ -f "$STATE/wvkbd.pid" ]; then
        kill "$(cat "$STATE/wvkbd.pid")" 2>/dev/null || true
      fi

      # Stop the exit button (harmless if it's the parent that called us — we get
      # orphaned to init and finish cleanup).
      if [ -f "$STATE/button.pid" ]; then
        kill "$(cat "$STATE/button.pid")" 2>/dev/null || true
      fi

      # Restore landscape.
      niri msg output eDP-1 transform normal || true

      rm -rf "$STATE"
      notify-send "Tablet mode" "Back to laptop mode." || true
    '';
  };

  # Show/hide the on-screen keyboard. wvkbd starts hidden (--hidden) so it doesn't
  # permanently eat the screen; SIGUSR2 shows it, SIGUSR1 hides it. We track the
  # current state with a flag file so a single button toggles.
  tablet-osk-toggle = pkgs.writeShellApplication {
    name = "tablet-osk-toggle";
    runtimeInputs = [ pkgs.coreutils pkgs.procps ];
    text = ''
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/tablet-mode"
      [ -f "$STATE/wvkbd.pid" ] || exit 0
      pid=$(cat "$STATE/wvkbd.pid")
      if [ -f "$STATE/osk.shown" ]; then
        kill -USR1 "$pid" 2>/dev/null || true   # hide
        rm -f "$STATE/osk.shown"
      else
        kill -USR2 "$pid" 2>/dev/null || true   # show
        touch "$STATE/osk.shown"
      fi
    '';
  };

  tablet-exit-button = pkgs.writeShellApplication {
    name = "tablet-exit-button";
    runtimeInputs = [ pkgs.yad tablet-osk-toggle tablet-mode-off ];
    text = ''
      # Blocks until the user touches Exit (or closes the window), then exits tablet
      # mode. yad is a direct child, so the wait is reliable. Compact corner panel —
      # niri parks it top-right (window-rule default-floating-position). Two buttons:
      #   ⌨ Keyboard — summon/dismiss the OSK (a command button: yad runs it and the
      #                panel stays open, because the response is a command not a number).
      #   ⟲ Exit     — response code 0 closes yad, which triggers tablet-mode-off.
      yad --class=tablet-exit --name=tablet-exit --title="Tablet Mode" \
          --text="Tablet mode" \
          --button="⌨   Keyboard:${tablet-osk-toggle}/bin/tablet-osk-toggle" \
          --button="⟲   Exit:0" \
          --buttons-layout=center --no-escape --sticky --skip-taskbar --undecorated \
          --borders=6 --width=320 --height=100 >/dev/null 2>&1 || true
      tablet-mode-off
    '';
  };

  tablet-mode-on = pkgs.writeShellApplication {
    name = "tablet-mode-on";
    runtimeInputs = baseInputs ++ [ pkgs.evtest pkgs.wvkbd tablet-exit-button ];
    text = ''
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/tablet-mode"
      if [ -d "$STATE" ]; then
        notify-send "Tablet mode" "Already in tablet mode." || true
        exit 0
      fi

      resolve_event() {
        local target="$1" name ev
        for ev in /sys/class/input/event*; do
          name=$(cat "$ev/device/name" 2>/dev/null) || continue
          if [ "$name" = "$target" ]; then
            echo "/dev/input/$(basename "$ev")"
            return 0
          fi
        done
        return 1
      }

      # ── SAFETY GATE ────────────────────────────────────────────────────────
      # Bring up the touch-reachable EXIT control first. If it can't launch, abort
      # and leave the keyboard/touchpad working. Never disable inputs without a way back.
      tablet-exit-button &
      BTN_PID="$!"
      sleep 0.4
      if ! kill -0 "$BTN_PID" 2>/dev/null; then
        notify-send "Tablet mode" "Exit control failed to launch — aborting, inputs left on." || true
        echo "exit button failed to launch; not disabling inputs" >&2
        exit 1
      fi

      mkdir -p "$STATE"
      echo "$BTN_PID" > "$STATE/button.pid"

      # ── Rotate to portrait ─────────────────────────────────────────────────
      niri msg output eDP-1 transform "${portraitTransform}" || true

      # ── On-screen keyboard (starts hidden; summon via the panel's Keyboard button) ─
      wvkbd-mobintl --hidden >/dev/null 2>&1 &
      echo "$!" > "$STATE/wvkbd.pid"

      # ── Disable keyboard + touchpad (exclusive evdev grab) ─────────────────
      # Touchscreen + stylus stay live. evtest --grab holds EVIOCGRAB until killed.
      : > "$STATE/grab.pids"
      for name in "${keyboardName}" "${touchpadName}"; do
        if dev=$(resolve_event "$name"); then
          evtest --grab "$dev" >/dev/null 2>&1 &
          echo "$!" >> "$STATE/grab.pids"
        else
          echo "warning: input device not found: $name" >&2
        fi
      done

      notify-send "Tablet mode" "Portrait • keyboard/touchpad off • touch the on-screen button to exit." || true
    '';
  };

  tablet-toggle = pkgs.writeShellApplication {
    name = "tablet-toggle";
    runtimeInputs = [ tablet-mode-on tablet-mode-off ];
    text = ''
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/tablet-mode"
      if [ -d "$STATE" ]; then
        tablet-mode-off
      else
        tablet-mode-on
      fi
    '';
  };
in {
  environment.systemPackages = [
    tablet-mode-on
    tablet-mode-off
    tablet-exit-button
    tablet-toggle
  ];
}
