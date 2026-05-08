#!/usr/bin/env bash
# update-fleet.sh — flake update + rebuild all managed NixOS hosts.
#
# Usage:
#   ./scripts/update-fleet.sh                  # full update + rebuild all hosts
#   ./scripts/update-fleet.sh --no-update       # skip flake update, just rebuild
#   ./scripts/update-fleet.sh --skip-local      # skip flipper (local rebuild)
#   ./scripts/update-fleet.sh --boot            # use 'boot' instead of 'switch' (requires reboot)
#   ./scripts/update-fleet.sh fivenix ntfy      # rebuild specific hosts only
#   ./scripts/update-fleet.sh --no-update fivenix  # combo
#   ./scripts/update-fleet.sh --boot ntfy langlab omada  # boot specific hosts
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

# ── Host definitions ──────────────────────────────────────────────────────────
# All remote hosts are on Tailscale (vimba-stairs.ts.net).
# VLAN 20 hosts (ntfy, langlab, omada) are not directly reachable from flipper
# without Tailscale — no LAN fallback for those.

declare -A SSH_TARGET    # primary: Tailscale MagicDNS
declare -A SSH_FALLBACK  # fallback: LAN IP (only for hosts reachable without Tailscale)
declare -A SSH_FLAGS     # extra nixos-rebuild flags per host

SSH_TARGET[fivenix]="robie@fivenix.vimba-stairs.ts.net"
SSH_FALLBACK[fivenix]="robie@192.168.7.137"
SSH_FLAGS[fivenix]="--sudo"

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

  extra_flags="${SSH_FLAGS[$host]:-}"

  # shellcheck disable=SC2086  # word splitting on flags is intentional
  if NIX_SSHOPTS="$NIX_SSH_EXTRA" \
       nixos-rebuild "$NR_ACTION" \
         --flake ".#$host" \
         --target-host "$TARGET" \
         $extra_flags; then
    ok "$host done"
    if [[ "$NR_ACTION" == boot ]]; then
      info "Rebooting $host..."
      ssh $NIX_SSH_EXTRA "$TARGET" reboot || true
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
