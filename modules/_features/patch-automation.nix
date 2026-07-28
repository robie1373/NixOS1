# modules/_features/patch-automation.nix
#
# Staggered, unattended patch days (ledger patch-automation.md; Robie 2026-07-06).
# Two phases, two options — enable each where it belongs:
#
#   phase1 (ONE host, or clauded later): the lock-bump robot. nix flake update →
#     build EVERY fleet host as the gate → commit+push flake.lock → ntfy report.
#     Nothing deploys in phase 1; a failed build = no push, fleet stays known-good.
#   phase2 (every vhost): on its set's day, pull the repo, build+stage the new
#     generation (nixos-rebuild boot), stop guests owning class-2 volumes and DELETE
#     those volume images (doctrine law 8 — the deletion audit extended into the
#     reboot-exempt place), then reboot into the new generation. Guests restart,
#     microvm.nix recreates missing volumes, services rehydrate. Failure surfaces
#     via the alerting spine (InstanceDown), not via a human watching.
#
# ⛔ ROBIE-GATE before enabling either phase: both need a GIT DEPLOY KEY (read for
# phase2, read+write for phase1) — the first standing off-op push credential in the
# lab. Hosts legitimately hold unattended credentials (doctrine law 3: secrets live
# at the host layer), but MINTING it is Robie's call: GitHub → NixOS1 repo →
# Settings → Deploy keys (write access for phase1's), then agenix-encrypt as
# patch-deploy-key.age to [ admin <phase-hosts> ]. Until then: modules present,
# nothing enabled, zero behavior change.

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.patchAutomation;

  gitEnv = ''
    export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i ${config.age.secrets.patch-deploy-key.path} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    export PATH=${lib.makeBinPath [ pkgs.git pkgs.nix pkgs.coreutils pkgs.curl pkgs.hostname ]}:$PATH
  '';

  ntfySend = title: prio: msg: ''
    topic=$(cat ${config.age.secrets.ntfy-alert-topic.path} 2>/dev/null || true)
    [ -n "$topic" ] && curl -fsS -m 10 -H "Title: ${title}" -H "Priority: ${prio}" \
      -d "${msg}" "${cfg.ntfyUrl}/$topic" >/dev/null 2>&1 || true
  '';

  workdir = "/var/lib/patch-automation/nixos-config";

  syncRepo = ''
    mkdir -p /var/lib/patch-automation
    if [ -d ${workdir}/.git ]; then
      git -C ${workdir} fetch origin && git -C ${workdir} reset --hard origin/${cfg.branch}
    else
      git clone --branch ${cfg.branch} ${cfg.repoUrl} ${workdir}
    fi
  '';

  phase1Script = pkgs.writeShellScript "patch-phase1" ''
    set -u
    ${gitEnv}
    ${syncRepo}
    cd ${workdir}
    old=$(sha256sum flake.lock)
    nix flake update 2>&1 | tail -5
    new=$(sha256sum flake.lock)
    if [ "$old" = "$new" ]; then echo "phase1: lock unchanged, nothing to do"; exit 0; fi
    for h in ${lib.concatStringsSep " " cfg.phase1.gateHosts}; do
      echo "phase1: build-gating $h"
      if ! nix build .#nixosConfigurations.$h.config.system.build.toplevel --no-link; then
        ${ntfySend "⚠️ patch phase1: build gate FAILED" "default"
          "nixpkgs bump broke the build for $h - lock NOT pushed, fleet stays on known-good. Fix manually."}
        exit 1
      fi
    done
    git add flake.lock
    git -c user.name=patch-robot -c user.email=patch-robot@home.lab \
      commit -m "flake.lock: automated bump (patch-automation phase 1)

All gate hosts built: ${lib.concatStringsSep ", " cfg.phase1.gateHosts}."
    git push origin ${cfg.branch}
    ${ntfySend "🟢 patch phase1: lock bumped + pushed" "min"
      "All gate hosts built clean. Set days will apply it."}
    # Advisory (non-blocking): fleet is already pushed above. These hosts are
    # decoupled from fleet health — a failure warns, it does NOT roll anything back.
    ${lib.optionalString (cfg.phase1.advisoryHosts != [ ]) ''
      for h in ${lib.concatStringsSep " " cfg.phase1.advisoryHosts}; do
        echo "phase1: advisory build $h (non-blocking; fleet lock already pushed)"
        if ! nix build .#nixosConfigurations.$h.config.system.build.toplevel --no-link; then
          ${ntfySend "⚠️ patch phase1: advisory host did not build" "default"
            "$h (advisory/desktop, not a fleet host) will NOT build the new lock. The fleet push already went through - this is only a heads-up. Fix $h before its next manual switch."}
        fi
      done
    ''}
  '';

  phase2Script = pkgs.writeShellScript "patch-phase2" ''
    set -u
    ${gitEnv}
    ${syncRepo}
    cd ${workdir}
    applied=$(readlink /run/current-system || true)
    target=$(nix build .#nixosConfigurations.$(hostname).config.system.build.toplevel --no-link --print-out-paths)
    if [ "$applied" = "$target" ]; then
      echo "phase2: already on target generation, nothing to do"; exit 0
    fi
    ${pkgs.nixos-rebuild}/bin/nixos-rebuild boot --flake ${workdir}#$(hostname)
    # Law 8: wipe class-2 volumes behind stopped guests; reboot rehydrates.
    ${lib.concatMapStringsSep "\n" (v: ''
      systemctl stop microvm@${v.guest} || true
      rm -f ${v.image}
      echo "phase2: wiped class-2 volume ${v.image} (guest ${v.guest})"
    '') cfg.phase2.class2Volumes}
    ${ntfySend "🟢 patch phase2: $(hostname) rebooting into new generation" "min"
      "Class-2 wipes done. If this host does not come back, InstanceDown will page."}
    systemctl reboot
  '';
in
{
  options.mySystem.patchAutomation = {
    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "git@github.com:robie1373/NixOS1.git";
      description = "Flake repo (deploy-key access).";
    };
    branch = lib.mkOption { type = lib.types.str; default = "main"; };
    ntfyUrl = lib.mkOption { type = lib.types.str; default = "http://192.168.20.10"; };

    phase1 = {
      enable = lib.mkEnableOption "the lock-bump robot (exactly ONE host)";
      onCalendar = lib.mkOption {
        type = lib.types.str; default = "Fri,Mon 01:00";
        description = "Runs before each set day so the gate result is fresh.";
      };
      gateHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "vhost1" "vhost2" ];
        description = ''
          BLOCKING gate: every host that must build before the lock is pushed.
          A failure here aborts the push — the fleet stays on known-good.
          Keep this to hosts that auto-apply (the phase-2 vhosts); a desktop
          that only ever applies manually belongs in advisoryHosts, not here.
        '';
      };
      advisoryHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          NON-BLOCKING gate: built AFTER the lock is already pushed. A failure
          here only sends a warning ntfy — it never blocks the fleet. For hosts
          decoupled from fleet health (e.g. flipper, a desktop full of packages
          the fleet never runs) that you still want an early heads-up on before
          your next manual switch. See ledger patch-automation.md.
        '';
      };
    };

    phase2 = {
      enable = lib.mkEnableOption "scheduled apply + class-2 wipe + reboot (each vhost)";
      onCalendar = lib.mkOption {
        type = lib.types.str; example = "Sat 03:00";
        description = "This host's set day (stagger: redundant pairs straddle sets).";
      };
      class2Volumes = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            guest = lib.mkOption { type = lib.types.str; };
            image = lib.mkOption { type = lib.types.str; };
          };
        });
        default = [];
        description = "Class-2 volume images to wipe each patch day (doctrine law 8). Class-3/4 volumes NEVER go here.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.phase1.enable || cfg.phase2.enable) {
      age.secrets.patch-deploy-key = {
        file = ../../secrets/patch-deploy-key.age;
        mode = "0400";
      };
      # Same declaration as alerting.nix (identical values merge cleanly) — this
      # module runs on hosts that don't import alerting.nix.
      age.secrets.ntfy-alert-topic = {
        file = ../../secrets/ntfy-alert-topic.age;
        mode = "0444";
      };
    })
    (lib.mkIf cfg.phase1.enable {
      systemd.services.patch-phase1 = {
        description = "Patch automation phase 1: flake lock bump + fleet build gate";
        serviceConfig = { Type = "oneshot"; ExecStart = "${phase1Script}"; };
      };
      systemd.timers.patch-phase1 = {
        wantedBy = [ "timers.target" ];
        timerConfig = { OnCalendar = cfg.phase1.onCalendar; Persistent = true; RandomizedDelaySec = "15min"; };
      };
    })
    (lib.mkIf cfg.phase2.enable {
      systemd.services.patch-phase2 = {
        description = "Patch automation phase 2: apply staged lock, wipe class-2 volumes, reboot";
        serviceConfig = { Type = "oneshot"; ExecStart = "${phase2Script}"; };
      };
      systemd.timers.patch-phase2 = {
        wantedBy = [ "timers.target" ];
        timerConfig = { OnCalendar = cfg.phase2.onCalendar; Persistent = true; RandomizedDelaySec = "15min"; };
      };
    })
  ];
}
