# modules/_features/net-speed.nix
#
# net-speed — interactive host-to-host LAN speed test using iperf3.
#
# Usage: net-speed <target> [--duration N] [--streams N] [--port N] [--no-reverse]
#
# Bootstraps the remote iperf3 server on-demand via SSH + nix-shell. No packages
# need to be pre-installed on the target — only Nix and key-based SSH access.
#
# Imported by server-common.nix so all lab hosts have it in $PATH.

{ pkgs, ... }:

let
  net-speed = pkgs.writeShellApplication {
    name = "net-speed";
    runtimeInputs = with pkgs; [ iperf3 jq iproute2 openssh ];
    text = ''
      # ── Defaults ────────────────────────────────────────────────────────────
      duration=10
      streams=4
      port=5201
      skip_reverse=0
      target=""

      # ── Colors ──────────────────────────────────────────────────────────────
      RED=$'\033[0;31m'
      GREEN=$'\033[0;32m'
      YELLOW=$'\033[1;33m'
      BLUE=$'\033[0;34m'
      CYAN=$'\033[0;36m'
      BOLD=$'\033[1m'
      DIM=$'\033[2m'
      NC=$'\033[0m'

      # ── Usage ────────────────────────────────────────────────────────────────
      usage() {
        printf 'Usage: net-speed <target> [options]\n\n'
        printf '  target         hostname or IP of a remote NixOS host\n'
        printf '  --duration N   seconds per test          (default: 10)\n'
        printf '  --streams N    parallel TCP streams       (default: 4)\n'
        printf '  --port N       iperf3 listening port      (default: 5201)\n'
        printf '  --no-reverse   upload only, skip download test\n'
      }

      # ── Argument parsing ─────────────────────────────────────────────────────
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --duration)   duration="$2";  shift 2 ;;
          --streams)    streams="$2";   shift 2 ;;
          --port)       port="$2";      shift 2 ;;
          --no-reverse) skip_reverse=1; shift   ;;
          -h|--help)    usage; exit 0   ;;
          -*)
            printf '%bUnknown option: %s%b\n' "$RED" "$1" "$NC" >&2
            exit 1
            ;;
          *)            target="$1";    shift   ;;
        esac
      done

      if [[ -z "$target" ]]; then
        printf '%bError:%b target host is required\n' "$RED" "$NC" >&2
        usage >&2
        exit 1
      fi

      # ── Helpers ──────────────────────────────────────────────────────────────
      local_host=$(hostname -s)
      HR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      fmt_speed() {
        awk -v bps="$1" 'BEGIN {
          if      (bps >= 1e9) printf "%.2f Gbps", bps / 1e9
          else if (bps >= 1e6) printf "%.1f Mbps", bps / 1e6
          else                 printf "%.0f Kbps", bps / 1e3
        }'
      }

      fmt_bytes() {
        awk -v b="$1" 'BEGIN {
          if      (b >= 1073741824) printf "%.1f GBytes", b / 1073741824
          else if (b >= 1048576)    printf "%.1f MBytes", b / 1048576
          else                      printf "%.0f KBytes", b / 1024
        }'
      }

      # Progress bar relative to 2.5 GbE (the core switch port speed).
      # Adjust max_bps if testing against a 1 GbE host.
      progress_bar() {
        local bps="$1"
        local bar_width=24
        local max_bps=2500000000

        local pct filled color
        pct=$(awk -v b="$bps" -v m="$max_bps" \
          'BEGIN { p = int(b*100/m); if (p > 100) p = 100; print p }')
        filled=$(awk -v p="$pct" -v w="$bar_width" \
          'BEGIN { print int(w * p / 100) }')

        if   [[ "$pct" -ge 80 ]]; then color="$GREEN"
        elif [[ "$pct" -ge 50 ]]; then color="$YELLOW"
        else                           color="$RED"
        fi

        printf '%s[' "$color"
        local i
        for (( i=0; i<filled; i++ ));           do printf '█'; done
        for (( i=filled; i<bar_width; i++ ));   do printf '░'; done
        printf '] %d%%%s of 2.5GbE' "$pct" "$NC"
      }

      # ── Connectivity check ───────────────────────────────────────────────────
      printf '\n%s%s%s\n' "$BOLD" "$HR" "$NC"
      printf '  net-speed  %s -> %s\n' "$local_host" "$target"
      printf '%s%s%s\n\n' "$DIM" "$HR" "$NC"

      printf '  Checking SSH access to %s... ' "$target"
      if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$target" true 2>/dev/null; then
        printf '%bfailed%b\n' "$RED" "$NC"
        printf '  Ensure key-based SSH auth is configured for %s\n' "$target" >&2
        exit 1
      fi
      printf '%bok%b\n' "$GREEN" "$NC"

      local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
      target_ip=$(ssh -o BatchMode=yes "$target" \
        "hostname -I 2>/dev/null | awk '{print \$1}'" 2>/dev/null \
        || printf '%s' "$target")

      printf '\n%s%s%s\n' "$BOLD" "$HR" "$NC"
      printf '  %s -> %s\n' "$local_ip" "$target_ip"
      printf '  %d streams  %ds per test  TCP\n' "$streams" "$duration"
      printf '%s%s%s\n\n' "$DIM" "$HR" "$NC"

      # ── Cleanup trap ─────────────────────────────────────────────────────────
      # Belt-and-suspenders: pkill any lingering iperf3 server on exit.
      # --one-off ensures normal self-cleanup; this catches aborted runs.
      cleanup() {
        ssh -o BatchMode=yes -o ConnectTimeout=3 "$target" \
          "pkill -f 'iperf3 -s' 2>/dev/null; true" 2>/dev/null || true
      }
      trap cleanup EXIT

      # ── Remote server lifecycle ──────────────────────────────────────────────
      SERVER_PID=0

      start_server() {
        # Bootstrap iperf3 on the remote via SSH + nix-shell.
        # Non-interactive SSH doesn't source /etc/profile, so NIX_PATH isn't set.
        # bash -l gives a login shell that sources /etc/profile and gets NIX_PATH.
        # Works regardless of the user's default shell (fish, zsh, etc.).
        # --one-off: server exits automatically after one client — no manual cleanup.
        # SC2029: $port is intentionally expanded locally before SSH receives the command.
        # shellcheck disable=SC2029
        ssh -o BatchMode=yes "$target" \
          "bash -l -c 'nix-shell -p iperf3 --run \"iperf3 -s --one-off -p $port\"'" \
          >/dev/null 2>&1 &
        SERVER_PID=$!
      }

      wait_for_server() {
        local attempts=0
        # All output here goes to stderr — run_test is called in a command
        # substitution, so anything on stdout would be captured into the result
        # variable and corrupt the iperf3 JSON.
        printf '  Waiting for server on %s:%s...' "$target" "$port" >&2
        # Poll via SSH until iperf3 is listening. Handles variable nix-shell
        # startup time — fast on warm cache, up to ~30s on cold cache.
        # SC2029: $port intentionally expanded locally.
        # shellcheck disable=SC2029
        while ! ssh -o BatchMode=yes -o ConnectTimeout=3 "$target" \
          "ss -tlnp 2>/dev/null | grep -q ':$port'" 2>/dev/null; do
          sleep 1
          attempts=$(( attempts + 1 ))
          if [[ $attempts -ge 30 ]]; then
            printf ' %btimed out%b\n' "$RED" "$NC" >&2
            return 1
          fi
        done
        printf ' %bready%b\n' "$GREEN" "$NC" >&2
      }

      # ── Single test ──────────────────────────────────────────────────────────
      run_test() {
        local rev_flag="$1"  # "" for upload, "-R" for download

        start_server
        local server_pid="$SERVER_PID"

        if ! wait_for_server; then
          kill "$server_pid" 2>/dev/null || true
          printf '{}'
          return 1
        fi

        local result
        # SC2086: rev_flag is intentionally unquoted — empty string or "-R"
        # shellcheck disable=SC2086
        result=$(iperf3 -c "$target" -p "$port" \
          -t "$duration" -P "$streams" $rev_flag --json 2>/dev/null) \
          || result='{}'

        wait "$server_pid" 2>/dev/null || true
        printf '%s' "$result"
      }

      # ── Display a test result ────────────────────────────────────────────────
      display_result() {
        local direction="$1"  # "upload" or "download"
        local json="$2"

        local bps bytes retransmits speed_str bytes_str arrow color from_host to_host

        if [[ "$direction" == "upload" ]]; then
          arrow="↑ Upload  "; color="$CYAN"
          from_host="$local_host"; to_host="$target"
          bps=$(printf '%s' "$json"         | jq '.end.sum_sent.bits_per_second // 0 | floor')
          bytes=$(printf '%s' "$json"       | jq '.end.sum_sent.bytes // 0')
          retransmits=$(printf '%s' "$json" | jq '.end.sum_sent.retransmits // 0')
        else
          arrow="↓ Download"; color="$BLUE"
          from_host="$target"; to_host="$local_host"
          bps=$(printf '%s' "$json"   | jq '.end.sum_received.bits_per_second // 0 | floor')
          bytes=$(printf '%s' "$json" | jq '.end.sum_received.bytes // 0')
          retransmits=0
        fi

        speed_str=$(fmt_speed "$bps")
        bytes_str=$(fmt_bytes "$bytes")

        printf '\n  %s%s %s%s  %s -> %s  (%d streams, %ds)\n' \
          "$color" "$BOLD" "$arrow" "$NC" \
          "$from_host" "$to_host" "$streams" "$duration"
        printf '  ──────────────────────────────────────────────────────\n'
        printf '  Throughput:   %s%s%s\n' "$BOLD" "$speed_str" "$NC"
        printf '  Transferred:  %s\n' "$bytes_str"
        printf '  Progress:     '
        progress_bar "$bps"
        printf '\n'
        if [[ "$retransmits" -gt 0 ]]; then
          printf '  %s⚠ Retransmits: %d%s\n' "$YELLOW" "$retransmits" "$NC"
        fi
      }

      # ── Run tests ────────────────────────────────────────────────────────────
      upload_bps=0
      download_bps=0
      upload_result=""
      download_result=""

      printf '  %sStarting upload test (local -> remote)...%s\n' "$DIM" "$NC"
      upload_result=$(run_test "")
      display_result "upload" "$upload_result"
      upload_bps=$(printf '%s' "$upload_result" \
        | jq '.end.sum_sent.bits_per_second // 0 | floor')

      if [[ $skip_reverse -eq 0 ]]; then
        printf '\n  %sStarting download test (remote -> local)...%s\n' "$DIM" "$NC"
        download_result=$(run_test "-R")
        display_result "download" "$download_result"
        download_bps=$(printf '%s' "$download_result" \
          | jq '.end.sum_received.bits_per_second // 0 | floor')
      fi

      # ── Summary ──────────────────────────────────────────────────────────────
      printf '\n%s%s%s\n' "$BOLD" "$HR" "$NC"
      printf '  %sSummary%s  %s -> %s\n' "$BOLD" "$NC" "$local_host" "$target"
      printf '  ──────────────────────────────────────────────────────\n'
      printf '  ↑ Upload:    %s%s%s\n' "$BOLD" "$(fmt_speed "$upload_bps")" "$NC"

      if [[ $skip_reverse -eq 0 ]]; then
        printf '  ↓ Download:  %s%s%s\n' "$BOLD" "$(fmt_speed "$download_bps")" "$NC"

        asymmetry=$(awk -v u="$upload_bps" -v d="$download_bps" 'BEGIN {
          if (u > 0 && d > 0) {
            diff = (u > d) ? u - d : d - u
            ref  = (u > d) ? d : u
            printf "%.0f", diff / ref * 100
          } else { print "0" }
        }')
        if [[ "$asymmetry" -gt 15 ]]; then
          printf '  %s⚠  %d%% asymmetry between directions%s\n' \
            "$YELLOW" "$asymmetry" "$NC"
        fi
      fi

      printf '%s%s%s\n\n' "$DIM" "$HR" "$NC"
    '';
  };
in
{
  environment.systemPackages = [ net-speed ];
}
