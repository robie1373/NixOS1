#!/usr/bin/env bash
# update-fleet.sh — flake update + rebuild all managed NixOS hosts.
#
# Remote hosts are rebooted after a successful switch by default (Chaos Monkey principle:
# everything must survive a reboot). Use --no-reboot to skip. flipper is never
# auto-rebooted — a reminder is printed at the end if it was updated.
#
# Usage:
#   ./scripts/update-fleet.sh                       # full update + rebuild + reboot remotes
#   ./scripts/update-fleet.sh --no-reboot           # update + rebuild, skip reboots
#   ./scripts/update-fleet.sh --no-update            # skip flake update, just rebuild
#   ./scripts/update-fleet.sh --skip-local           # skip flipper (local rebuild)
#   ./scripts/update-fleet.sh fivenix ntfy           # rebuild specific hosts only
#   ./scripts/update-fleet.sh --no-update fivenix    # combo
#
# Auth order for each remote host (Tailscale removed 2026-06-22 — fleet reaches hosts
# over the wired LAN via home.lab names; Tailscale is no longer load-bearing here):
#   1. SSH to the LAN target (home.lab name / IP) — uses whatever is in the SSH agent (1Password)
#   2. SSH to the LAN target — key loaded explicitly from 1Password via `op read`
#
# Before first run:
#   - Verify OP_SSH_KEY_REF below matches your actual 1Password item.
#     Find it with: op item list --format=json | jq -r '.[].title'
#     Then: op item get "My SSH Key" --fields label=private_key

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

FLAKE="$HOME/nixos-config"

# 1Password secret reference for the SSH private key used to reach remote hosts.
# Override via environment: OP_SSH_KEY_REF="op://..." ./scripts/update-fleet.sh
OP_SSH_KEY_REF="${OP_SSH_KEY_REF:-op://Personal/SSH Key/private key}"

# Minimum free space required on /nix before deploying, in MiB.
DISK_THRESHOLD_MIB="${DISK_THRESHOLD_MIB:-2048}"

# Seconds to wait for a host to come back after reboot before giving up.
REBOOT_TIMEOUT="${REBOOT_TIMEOUT:-180}"

# ── Host definitions ──────────────────────────────────────────────────────────
# Remote hosts are reached over the wired LAN by their home.lab names (resolved by
# dns1/Blocky). VLAN 20 hosts (ntfy, langlab, omada) ARE directly reachable from
# flipper over the LAN (verified 2026-06-22). fivenix has no home.lab record yet —
# use its LAN IP; it's the dual-boot rig, only reachable when booted to NixOS.

declare -A SSH_TARGET    # LAN target: home.lab name or IP
declare -A SSH_FLAGS     # extra nixos-rebuild flags per host

# fivenix: Windows-only until further notice (2026-06-23). Was the dual-boot
# rig; its NixOS install is not in service. Re-enable here + in REMOTE_HOSTS
# when it's booting NixOS again. Needs --sudo --ask-sudo-password (robie user,
# interactive — can't be driven non-interactively).
# SSH_TARGET[fivenix]="robie@192.168.7.137"
# SSH_FLAGS[fivenix]="--sudo --ask-sudo-password"

SSH_TARGET[ntfy]="root@ntfy.home.lab"
SSH_FLAGS[ntfy]=""

SSH_TARGET[langlab]="root@langlab.home.lab"
SSH_FLAGS[langlab]=""

SSH_TARGET[omada]="root@omada.home.lab"
SSH_FLAGS[omada]=""

# nixos1: local QEMU/KVM VM — SSH target unknown; uncomment when known.
# SSH_TARGET[nixos1]="root@nixos1.home.lab"
# SSH_FLAGS[nixos1]=""

REMOTE_HOSTS=(ntfy langlab omada)   # fivenix Windows-only — see above

# ── Arg parsing ───────────────────────────────────────────────────────────────

SKIP_UPDATE=false
SKIP_LOCAL=false
REBOOT=true
NR_ACTION=switch
HOSTS_FILTER=()
FLIPPER_UPDATED=false

usage() {
  grep '^# ' "$0" | head -20 | sed 's/^# //'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-update)  SKIP_UPDATE=true; shift ;;
    --skip-local) SKIP_LOCAL=true;  shift ;;
    --no-reboot)  REBOOT=false;     shift ;;
    -h|--help)    usage ;;
    -*)           echo "Unknown option: $1" >&2; exit 1 ;;
    *)            HOSTS_FILTER+=("$1"); shift ;;
  esac
done

should_run() { [[ ${#HOSTS_FILTER[@]} -eq 0 ]] || printf '%s\n' "${HOSTS_FILTER[@]}" | grep -qx "$1"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
info() { printf '\033[0;37m  ~ %s\033[0m\n' "$*"; }

# Temp dir for OP key material; cleaned up on exit.
KEYDIR="$(mktemp -d)"
trap 'rm -rf "$KEYDIR"' EXIT

# Test if an SSH target accepts connections.
# Usage: ssh_connects [extra-ssh-opts...] -- user@host
ssh_connects() {
  local -a opts=()
  while [[ "$1" != "--" ]]; do opts+=("$1"); shift; done
  shift  # consume --
  local target="$1"

  ssh -o BatchMode=yes \
      -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no \
      "${opts[@]+"${opts[@]}"}" \
      "$target" true 2>/dev/null
}

# Load SSH private key from 1Password. Prints the keyfile path on success.
op_keyfile() {
  local keyfile="$KEYDIR/id_ed25519"
  [[ -f "$keyfile" ]] && { echo "$keyfile"; return 0; }  # cached

  if ! command -v op &>/dev/null; then
    err "op CLI not found — cannot load key from 1Password"
    return 1
  fi

  if op read "$OP_SSH_KEY_REF" > "$keyfile" 2>/dev/null; then
    chmod 600 "$keyfile"
    echo "$keyfile"
    return 0
  fi

  err "Failed to read key from 1Password: $OP_SSH_KEY_REF"
  err "Verify the secret reference and that 1Password is unlocked."
  return 1
}

# Resolve SSH target + options for a named host.
# On success, sets TARGET and NIX_SSH_EXTRA (for NIX_SSHOPTS).
resolve_ssh() {
  local name="$1"
  local primary="${SSH_TARGET[$name]}"

  TARGET=""
  NIX_SSH_EXTRA="-o StrictHostKeyChecking=no"

  # 1. LAN — agent (1Password) auth
  if ssh_connects -- "$primary"; then
    info "Connected via LAN (agent auth)"
    TARGET="$primary"
    return 0
  fi

  # 2. LAN — explicit 1Password key
  local keyfile
  if keyfile=$(op_keyfile 2>/dev/null); then
    if ssh_connects -i "$keyfile" -- "$primary"; then
      info "Connected via LAN (1Password key)"
      TARGET="$primary"
      NIX_SSH_EXTRA="-o StrictHostKeyChecking=no -i $keyfile"
      return 0
    fi
  fi

  err "$name: no reachable SSH route"
  return 1
}

# Check free space on /nix (or / if /nix is not a separate mount).
# Returns 1 and prints an error if below DISK_THRESHOLD_MIB.
check_disk_space() {
  local target="$1"
  local avail_kib
  avail_kib=$(ssh $NIX_SSH_EXTRA "$target" \
    "df --output=avail /nix 2>/dev/null || df --output=avail /" \
    | tail -1 | tr -d ' ')
  local avail_mib=$(( avail_kib / 1024 ))
  if [[ $avail_mib -lt $DISK_THRESHOLD_MIB ]]; then
    err "Disk space too low: ${avail_mib} MiB free (need ${DISK_THRESHOLD_MIB} MiB)"
    err "Run: ssh $target 'nix-collect-garbage -d' to free space"
    return 1
  fi
  info "Disk space OK: ${avail_mib} MiB free"
}

# After a reboot, poll until SSH comes back or timeout expires.
wait_for_ssh() {
  local target="$1"
  local deadline=$(( SECONDS + REBOOT_TIMEOUT ))
  info "Waiting for $target to come back (up to ${REBOOT_TIMEOUT}s)..."
  sleep 5  # give it a moment to start rebooting before we poll
  while [[ $SECONDS -lt $deadline ]]; do
    if ssh_connects $NIX_SSH_EXTRA -- "$target"; then
      return 0
    fi
    sleep 5
  done
  err "$target did not come back within ${REBOOT_TIMEOUT}s"
  return 1
}

# Report journal errors since the switch ran. Informational only — does not affect
# the FAILED list. If there's output, the operator decides whether it matters.
check_health() {
  local target="$1"
  local since="$2"
  local output
  output=$(ssh $NIX_SSH_EXTRA "$target" \
    "journalctl -b -p err --since '$since' --no-pager -q 2>/dev/null | head -30" || true)
  if [[ -n "$output" ]]; then
    warn "Activation requires review on $target:"
    printf '%s\n' "$output" | sed 's/^/    /'
  else
    ok "Activation clean"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

cd "$FLAKE"
FAILED=()

# 1. Flake update
if [[ "$SKIP_UPDATE" == false ]]; then
  log "Updating flake inputs..."
  nix flake update
  ok "flake.lock updated"
fi

# 2. Flipper (local)
if [[ "$SKIP_LOCAL" == false ]] && should_run flipper; then
  log "Rebuilding flipper (local, switch)..."
  if sudo nixos-rebuild switch --flake ".#flipper"; then
    ok "flipper done"
    FLIPPER_UPDATED=true
  else
    err "flipper FAILED"
    FAILED+=(flipper)
  fi
fi

# 3. Remote hosts
TARGET=""
NIX_SSH_EXTRA=""

for host in "${REMOTE_HOSTS[@]}"; do
  should_run "$host" || continue
  log "Deploying $host..."

  if ! resolve_ssh "$host"; then
    FAILED+=("$host")
    continue
  fi

  if ! check_disk_space "$TARGET"; then
    FAILED+=("$host")
    continue
  fi

  extra_flags="${SSH_FLAGS[$host]:-}"
  switch_time=$(date '+%Y-%m-%d %H:%M:%S')

  # shellcheck disable=SC2086  # word splitting on flags is intentional
  if NIX_SSHOPTS="$NIX_SSH_EXTRA" \
       nixos-rebuild switch \
         --flake ".#$host" \
         --target-host "$TARGET" \
         $extra_flags; then
    ok "$host deployed"

    if [[ "$REBOOT" == true ]]; then
      info "Rebooting $host..."
      ssh $NIX_SSH_EXTRA "$TARGET" reboot || true
      if wait_for_ssh "$TARGET"; then
        switch_time=$(date '+%Y-%m-%d %H:%M:%S')  # reset to post-reboot for health check
        check_health "$TARGET" "$switch_time"
        ok "$host back up"
      else
        FAILED+=("$host")
        continue
      fi
    else
      check_health "$TARGET" "$switch_time"
      ok "$host healthy"
    fi

  else
    err "$host FAILED"
    FAILED+=("$host")
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo
if [[ ${#FAILED[@]} -eq 0 ]]; then
  log "All hosts updated successfully."
else
  err "Failed hosts: ${FAILED[*]}"
fi

if [[ "$FLIPPER_UPDATED" == true && "$REBOOT" == true ]]; then
  warn "flipper was updated — reboot when ready: sudo reboot"
fi

[[ ${#FAILED[@]} -eq 0 ]] || exit 1
