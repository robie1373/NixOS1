# Flipper convertible / tablet mode (niri).
#
# Flipper (ASUS Vivobook 14 Flip TP3407SA) folds into a portrait tablet. There is
# no working accelerometer under Linux — the Intel ISH firmware for this ASUS SKU
# has not been upstreamed (see ledger flipper.md / flipper-tablet.md) — so there
# is no automatic rotation or fold detection. This is a *manual* toggle.
#
# Design notes:
#   * Rotation uses `niri msg output … transform` (runtime, temporary). niri 26.04
#     has no `set-output-transform` action; this subcommand is the replacement.
#   * Keyboard + touchpad are disabled with an exclusive evdev grab (evtest --grab),
#     NOT `hyprctl dispatch disabledevice` (a no-op under niri). robie is in the
#     `input` group, so the grab needs no root. The touchscreen + stylus (ILIT2901)
#     are deliberately left live as the primary escape hatch.
#   * The exit control is a noctalia bar button running `tablet-toggle`. This must
#     be a *layer-shell* surface: niri intercepts touch on floating windows for
#     window move/resize gestures and does not deliver taps to the client, so a
#     floating yad button was untappable by touch. The noctalia bar is layer-shell
#     (like wvkbd, whose keys take touch fine), so its buttons are touch-reliable.
#     Add the buttons via noctalia Settings → Bar (custom_button widgets):
#        command = "tablet-toggle"      glyph e.g. device-tablet
#        command = "tablet-osk-toggle"  glyph e.g. keyboard
#   * NEVER-STUCK GUARANTEE: inputs are only disabled if noctalia is running (the
#     bar carries the exit button). If noctalia isn't up, tablet-mode-on aborts
#     without grabbing. Backstops regardless: the touchscreen stays live, the OSK's
#     Enter reaches the focused surface (virtual keyboard, not grabbed), and
#     `tablet-mode-off` is reachable over SSH.
#
# Entry: the noctalia bar button, or Mod+Shift+T (while the keyboard still works).
# Exit:  the same bar button, or `tablet-mode-off` over SSH.
{ pkgs, ... }:
let
  # Kernel input device names (compositor-independent; from /sys/class/input/*/device/name).
  # Confirmed on flipper 2026-06-30. Verify with the same path after a kernel bump.
  keyboardName = "AT Translated Set 2 keyboard";
  touchpadName = "ASCP1205:00 093A:3020 Touchpad";

  # Portrait transform. niri "90" matches the Hyprland-era transform 1 (90°).
  # Confirmed correct orientation on hardware 2026-06-30. ("270" would be the other way.)
  portraitTransform = "90";

  baseInputs = with pkgs; [ niri coreutils procps libnotify util-linux ];

  tablet-mode-off = pkgs.writeShellApplication {
    name = "tablet-mode-off";
    runtimeInputs = baseInputs;
    text = ''
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/tablet-mode"
      # Serialize against tablet-mode-on. The mkdir mutex only guards enter-vs-enter;
      # without this lock an exit could sweep grabs + delete state while an enter was
      # still mid-spawn, orphaning whatever grab landed after the sweep (this left the
      # touchpad grabbed with no state dir on 2026-07-01).
      # -w 5 + proceed-anyway: the EXIT path must never block indefinitely — a held
      # lock (e.g. leaked into a long-lived process) would otherwise make tablet mode
      # inescapable. Proceeding unserialized is safe here: the pkill backstop below
      # kills every grab regardless of bookkeeping.
      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/tablet-mode.lock"
      flock -w 5 9 || echo "warning: lock timeout — proceeding with exit anyway" >&2

      # Idempotent: if we're not in tablet mode, do nothing. Safe to call from the
      # bar button, the toggle, and SSH concurrently.
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

      # Belt and braces: no matter what the pid bookkeeping says, no evdev grab or
      # OSK may survive tablet-mode-off. evtest and wvkbd have no other use on this
      # machine, so killing every instance is safe. This is the backstop that makes
      # a repeat of the 2026-07-01 stuck-keyboard incident impossible even if the
      # state files are wrong.
      pkill -f "evtest --grab" 2>/dev/null || true
      pkill -f "wvkbd-mobintl" 2>/dev/null || true

      # Restore landscape.
      niri msg output eDP-1 transform normal || true

      rm -rf "$STATE"
      notify-send "Tablet mode" "Back to laptop mode." || true
    '';
  };

  # Show/hide the on-screen keyboard. wvkbd starts hidden (--hidden) so it doesn't
  # permanently eat the screen; SIGUSR2 shows it, SIGUSR1 hides it. A flag file
  # tracks state so one button toggles.
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

  tablet-mode-on = pkgs.writeShellApplication {
    name = "tablet-mode-on";
    runtimeInputs = baseInputs ++ [ pkgs.evtest pkgs.wvkbd ];
    text = ''
      STATE="''${XDG_RUNTIME_DIR:-/tmp}/tablet-mode"
      # Serialize against tablet-mode-off (see comment there). Entry may simply give
      # up if the lock is busy — unlike exit, refusing to enter is always safe.
      exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/tablet-mode.lock"
      if ! flock -w 5 9; then
        notify-send "Tablet mode" "Busy — try again." || true
        exit 1
      fi

      # Atomic mkdir doubles as mutex + "already in tablet mode" check. A plain
      # [ -d ] guard raced: two taps of the bar button in quick succession both
      # passed the check, and the second instance truncated the first's grab.pids —
      # orphaning live evdev grabs that exit could no longer find (this locked up
      # the keyboard on 2026-07-01 and needed a power-button reboot).
      if ! mkdir "$STATE" 2>/dev/null; then
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
      # The exit control is the noctalia bar button. Never disable inputs unless
      # noctalia (hence the bar, hence the exit button) is actually running.
      if ! pgrep -x noctalia >/dev/null 2>&1; then
        notify-send "Tablet mode" "noctalia not running — refusing to disable inputs (no exit button)." || true
        echo "noctalia not running; not disabling inputs" >&2
        rmdir "$STATE" 2>/dev/null || true
        exit 1
      fi

      # ── Rotate to portrait ─────────────────────────────────────────────────
      niri msg output eDP-1 transform "${portraitTransform}" || true

      # ── On-screen keyboard (starts hidden; summon via the bar's Keyboard button) ─
      # 9>&- : long-lived children must NOT inherit the lock fd — flock lives until
      # the last fd closes, so an inherited fd 9 would keep the lock held for the
      # lifetime of wvkbd/evtest, deadlocking tablet-mode-off against the very
      # processes it needs to kill (locked Robie out of laptop mode on 2026-07-01).
      wvkbd-mobintl --hidden >/dev/null 2>&1 9>&- &
      echo "$!" > "$STATE/wvkbd.pid"

      # ── Wait for the Mod+Shift+T chord to be physically released ───────────
      # If we grab while the keys are still held, their release events go to the
      # grab instead of niri — niri then thinks the chord is stuck down and its
      # key-repeat re-fires the bind, toggling tablet mode in a rapid loop
      # (observed 2026-07-01). evtest --query exits 0 when a key is up, nonzero
      # when pressed. ~3s timeout so a stuck key can't block entry forever.
      if kbd=$(resolve_event "${keyboardName}"); then
        for _ in $(seq 1 60); do
          held=0
          for key in KEY_LEFTMETA KEY_RIGHTMETA KEY_LEFTSHIFT KEY_RIGHTSHIFT KEY_T; do
            if ! evtest --query "$kbd" EV_KEY "$key"; then held=1; fi
          done
          [ "$held" -eq 0 ] && break
          sleep 0.05
        done
      fi

      # ── Disable keyboard + touchpad (exclusive evdev grab) ─────────────────
      # Touchscreen + stylus stay live. evtest --grab holds EVIOCGRAB until killed.
      : > "$STATE/grab.pids"
      for name in "${keyboardName}" "${touchpadName}"; do
        if dev=$(resolve_event "$name"); then
          evtest --grab "$dev" >/dev/null 2>&1 9>&- &
          echo "$!" >> "$STATE/grab.pids"
        else
          echo "warning: input device not found: $name" >&2
        fi
      done

      notify-send "Tablet mode" "Portrait • keyboard/touchpad off • tap the bar button to exit." || true
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
    tablet-osk-toggle
    tablet-toggle
  ];
}
