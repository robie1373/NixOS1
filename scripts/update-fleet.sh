#!/usr/bin/env bash
# update-fleet.sh — flake update + rebuild all managed NixOS hosts.
#
# Usage:
#   ./scripts/update-fleet.sh                       # full update + rebuild all hosts
#   ./scripts/update-fleet.sh --no-update            # skip flake update, just rebuild
#   ./scripts/update-fleet.sh --skip-local           # skip flipper (local rebuild)
#   ./scripts/update-fleet.sh --boot                 # use 'boot' + reboot (for critical changes)
#   ./scripts/update-fleet.sh fivenix ntfy           # rebuild specific hosts only
#   ./scripts/update-fleet.sh --no-update fivenix    # combo
#   ./scripts/update-fleet.sh --boot ntfy langlab omada
#
# Auth order for each remote host:
#   1. SSH to Tailscale hostname — uses whatever is in the SSH agent (1Password)
#   2. SSH to Tailscale hostname — key loaded explicitly from 1Password via `op read`
#   3. SSH to fallback LAN IP  — with OP key (fivenix only; VLAN 20 unreachable without TS)
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
# All remote hosts are on Tailscale (vimba-stairs.ts.net).
# VLAN 20 hosts (ntfy, langlab, omada) are not directly reachable from flipper
# without Tailscale — no LAN fallback for those.

declare -A SSH_TARGET    # primary: Tailscale MagicDNS
declare -A SSH_FALLBACK  # fallback: LAN IP (only for hosts reachable without Tailscale)
declare -A SSH_FLAGS     # extra nixos-rebuild flags per host

SSH_TARGET[fivenix]="robie@fivenix.vimba-stairs.ts.net"
SSH_FALLBACK[fivenix]="robie@192.168.7.137"
SSH_FLAGS[fivenix]="--sudo --ask-sudo-password"

SSH_TARGET[ntfy]="root@ntfy.vimba-stairs.ts.net"
SSH_FLAGS[ntfy]=""

SSH_TARGET[langlab]="root@langlab.vimba-stairs.ts.net"
SSH_FLAGS[langlab]=""

SSH_TARGET[omada]="root@omada.vimba-stairs.ts.net"
SSH_FLAGS[omada]=""

# nixos1: local QEMU/KVM VM — SSH target unknown; uncomment when known.
# SSH_TARGET[nixos1]="root@nixos1.vimba-stairs.ts.net"
# SSH_FLAGS[nixos1]=""

REMOTE_HOSTS=(fivenix ntfy langlab omada)

# ── Arg parsing ───────────────────────────────────────────────────────────────

SKIP_UPDATE=false
SKIP_LOCAL=false
NR_ACTION=switch
HOSTS_FILTER=()

usage() {
  grep '^# ' "$0" | head -20 | sed 's/^# //'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-update)  SKIP_UPDATE=true; shift ;;
    --skip-local) SKIP_LOCAL=true;  shift ;;
    --boot)       NR_ACTION=boot;   shift ;;
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
  local fallback="${SSH_FALLBACK[$name]:-}"

  TARGET=""
  NIX_SSH_EXTRA="-o StrictHostKeyChecking=no"

  # 1. Tailscale — agent (1Password) auth
  if ssh_connects -- "$primary"; then
    info "Connected via Tailscale (agent auth)"
    TARGET="$primary"
    return 0
  fi

  # 2. Tailscale — explicit 1Password key
  local keyfile
  if keyfile=$(op_keyfile 2>/dev/null); then
    if ssh_connects -i "$keyfile" -- "$primary"; then
      info "Connected via Tailscale (1Password key)"
      TARGET="$primary"
      NIX_SSH_EXTRA="-o StrictHostKeyChecking=no -i $keyfile"
      return 0
    fi
  fi

  # 3. LAN fallback (agent auth) — only for hosts with a fallback defined
  if [[ -n "$fallback" ]]; then
    if ssh_connects -- "$fallback"; then
      info "Connected via LAN fallback (agent auth)"
      TARGET="$fallback"
      return 0
    fi

    # 4. LAN fallback — explicit 1Password key
    if [[ -n "${keyfile:-}" ]] && ssh_connects -i "$keyfile" -- "$fallback"; then
      info "Connected via LAN fallback (1Password key)"
      TARGET="$fallback"
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

# Check the journal for error-level entries since a given timestamp.
# Usage: check_health <ssh-target> <since-timestamp>
# <since-timestamp> is a string passed to journalctl --since (e.g. "2026-05-10 09:30:00").
# Only errors after the switch started are reported — pre-existing boot noise is ignored.
#
# Suppressed patterns (benign, host-specific):
#   kvm_intel          — nested virt unavailable in LXC containers
#   dbus-broker        — duplicate .service file names in NixOS path
#   ucsi_ccg           — USB-C controller init failure on fivenix (hardware quirk)
#   nvidia.*i2c        — Nvidia i2c timeout on fivenix (hardware quirk)
#   uvcvideo           — USB camera driver init on fivenix (hardware quirk)
#   sm-notify.*sm.bak  — NFS statd benign startup message
#   pam_env.*fcitx     — fcitx im= variable warning, harmless
#   useradd warning.*uid — Omada Docker container low-UID user, harmless
#   tail:.*inaccessible — Omada nightly log rotation artifact
check_health() {
  local target="$1"
  local since="${2:-$(date '+%Y-%m-%d %H:%M:%S')}"
  local errors
  errors=$(ssh $NIX_SSH_EXTRA "$target" \
    "journalctl -b -p err --since '$since' --no-pager -q 2>/dev/null | head -30" || true)
  errors=$(printf '%s\n' "$errors" \
    | grep -v "kvm_intel" \
    | grep -v "Ignoring duplicate name 'org.freedesktop" \
    | grep -v "ucsi_ccg" \
    | grep -v "nvidia.*i2c\|i2c.*nvidia" \
    | grep -v "uvcvideo" \
    | grep -v "sm-notify.*sm\.bak" \
    | grep -v "pam_env.*fcitx" \
    | grep -v "useradd warning.*uid" \
    | grep -v "tail:.*inaccessible\|tail:.*appeared" \
    | grep -v "^$")
  if [[ -n "$errors" ]]; then
    warn "Journal errors found on $target:"
    printf '%s\n' "$errors" | sed 's/^/    /'
    return 1
  fi
  ok "Health check passed: no journal errors"
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
  log "Rebuilding flipper (local, $NR_ACTION)..."
  if sudo nixos-rebuild "$NR_ACTION" --flake ".#flipper"; then
    ok "flipper done"
    [[ "$NR_ACTION" == boot ]] && info "Reboot flipper to activate."
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
  local switch_time
  switch_time=$(date '+%Y-%m-%d %H:%M:%S')

  # shellcheck disable=SC2086  # word splitting on flags is intentional
  if NIX_SSHOPTS="$NIX_SSH_EXTRA" \
       nixos-rebuild "$NR_ACTION" \
         --flake ".#$host" \
         --target-host "$TARGET" \
         $extra_flags; then
    ok "$host deployed"

    if [[ "$NR_ACTION" == boot ]]; then
      info "Rebooting $host..."
      ssh $NIX_SSH_EXTRA "$TARGET" reboot || true
      if wait_for_ssh "$TARGET"; then
        if ! check_health "$TARGET" "$switch_time"; then
          warn "$host came back but has journal errors — marking as failed"
          FAILED+=("$host")
          continue
        fi
        ok "$host healthy"
      else
        FAILED+=("$host")
        continue
      fi
    else
      # switch: host didn't reboot, check health in place
      if ! check_health "$TARGET" "$switch_time"; then
        warn "$host switched but has journal errors — marking as failed"
        FAILED+=("$host")
        continue
      fi
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
  exit 1
fi
