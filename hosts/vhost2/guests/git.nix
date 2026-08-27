# hosts/vhost2/guests/git.nix
#
# git — in-lab git server, as a microVM guest of vhost2 (new-service protocol run
# 2026-07-16, Fable 5; Robie approved the class-4 volume same day). Bare repos
# served over SSH to the `git` user (git-shell — push/pull only, no interactive
# shell). No web UI by design; Forgejo stays in the quiver if ever wanted.
#
# Guest host keys regenerate every boot (tmpfs /etc — doctrine option A, see
# ledger guest-hostkey-persistence.md): clients use StrictHostKeyChecking
# accept-new and re-trust after a guest restart (`ssh-keygen -R git.home.lab`).

{ inputs, config, lib, pkgs, ... }:

let
  # Locally-administered MAC. Mnemonic: VLAN 20, host octet 58.
  mac = "02:00:00:00:20:58";
  # Repos served. Adding one: append here, rebuild vhost2 — the init service is
  # idempotent and creates only what's missing (never deletes).
  repos = [
    "ledger2"        # THE Ledger — in-lab only, never GitHub (Robie, 2026-07-16)
    "nixos-config"
    "homeLab"
    "langlab"
    "qwak"
    "teacha"
    "nibbles"
    "languages"
    "pages-content"
    "work"           # Bearing operational state (TASKS/OBLIGATIONS/CLAUDE.md) — lab-local, never GitHub
    "test"           # probation/scratch repo (new-service protocol B3/B4)
  ];
  # sshd runs a forced command THROUGH the account's login shell. With shell =
  # git-shell that fails ("unrecognized command <script path>"), because git-shell
  # only accepts git verbs. So the login shell is bash and BOTH keys are confined by
  # their own forced command instead -- the restriction moved, it did not go away.
  # Any key added here without a command= would get a real shell; do not add one.
  adminGitShell = pkgs.writeShellScript "git-shell-all-repos" ''
    exec ${pkgs.git}/bin/git-shell -c "''${SSH_ORIGINAL_COMMAND:-}"
  '';

  # The patch robot's deploy key, scoped to nixos-config.git ONLY.
  #
  # The `git` user is shared by every repo above -- including ledger2 and work, which
  # hold Robie's personal and operational state and are deliberately never on GitHub.
  # The robot's key is an UNATTENDED credential held by the hypervisors, so it must not
  # inherit write access to the Ledger merely because it needs to bump a flake lock.
  # This forced command allowlists the two git verbs against the one repo path and
  # refuses everything else.
  #
  # Added 2026-08-21: the 2026-08-16 repoint (03e73df) moved the robot from GitHub to
  # this server but changed the URL without the credential, so its clone had been denied
  # ever since -- silently, because phase 1 read the failure as "lock unchanged".
  # See ledger patch-automation.md.
  patchRobotGitShell = pkgs.writeShellScript "patch-robot-git-shell" ''
    set -eu
    cmd="''${SSH_ORIGINAL_COMMAND:-}"
    case "$cmd" in
      "git-upload-pack '/var/lib/git/nixos-config.git'" | "git-upload-pack /var/lib/git/nixos-config.git" | "git-receive-pack '/var/lib/git/nixos-config.git'" | "git-receive-pack /var/lib/git/nixos-config.git")
        exec ${pkgs.git}/bin/git-shell -c "$cmd"
        ;;
      *)
        echo "patch-robot: this key is scoped to nixos-config.git; refused: $cmd" >&2
        exit 1
        ;;
    esac
  '';

  # The NAS mirror's key (git-mirror-key.age, held by vhost1). READ-ONLY: it
  # allowlists git-upload-pack only -- no receive-pack, so this credential cannot
  # write to the canonical store. That is the point. The mirror exists so the
  # Ledger survives the loss of this guest's single non-redundant disk; giving its
  # unattended key a write path back into the original would create a second way
  # to corrupt the thing being protected.
  #
  # `list-repos` is a deliberate extra verb. The mirror job asks the SERVER which
  # repos exist rather than carrying its own copy of the list -- a duplicated list
  # would drift the day a repo is added here, and the new repo would silently
  # never be mirrored. The `repos` list above is the single source of truth for both.
  # See modules/_features/git-nas-mirror.nix and ledger git.md.
  gitMirrorShell = pkgs.writeShellScript "git-mirror-shell" ''
    set -eu
    cmd="''${SSH_ORIGINAL_COMMAND:-}"
    case "$cmd" in
      list-repos)
        ${lib.concatMapStringsSep "\n        " (r: ''printf '%s\n' "${r}"'') repos}
        ;;
      "git-upload-pack /var/lib/git/"*".git" | "git-upload-pack '/var/lib/git/"*".git'")
        exec ${pkgs.git}/bin/git-shell -c "$cmd"
        ;;
      *)
        echo "git-mirror: this key is read-only (upload-pack + list-repos); refused: $cmd" >&2
        exit 1
        ;;
    esac
  '';

in
{
  imports = [
    ../../../modules/_system/server-common.nix   # ssh, agenix, observability agent, nix pinning
  ];

  networking.hostName = "git";

  # ── microVM runtime ──────────────────────────────────────────────────────────
  microvm = {
    hypervisor = "qemu";
    vcpu = 1;
    mem  = 1024;                      # git is light; NOT 2048 exactly (QEMU hang, microvm.nix #171)

    shares = [{
      source     = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag        = "ro-store";
      proto      = "virtiofs";
    }];

    # ══ COPYING THIS FILE FOR THE VOLUME? READ THIS FIRST ═══════════════════════
    # This guest has a volume because DURABILITY IS ITS JOB -- it is the canonical
    # store. That does NOT make it precedent for persisting a working copy.
    # A replica whose job is durability is licensed; a cache whose job is speed is
    # NOT. Purpose, not content. (Robie, 2026-08-06 -- after a session proposed five
    # volumes for guests that needed none: ledger2/doctrine-drift-audit.md.)
    # HARD RULE: before adding `volumes` to any guest, read
    # ledger2/stateless-doctrine.md (classification table + "The class-2 trap") and
    # the checklist in ledger2/doctrine-drift-audit.md. See dns2.nix for the four
    # questions. The stateless template is dns2.nix -- prefer it.
    # ════════════════════════════════════════════════════════════════════════════
    #
    # ── Licensed volume: CLASS 4 — bare git repositories, exactly /var/lib/git
    # Loss story (law 7): every repo has a full working copy on flipper (itself
    # restic'd nightly) and four have GitHub remotes; worst case = re-init + re-push.
    # Backed up: vhost2 restic set `git` (nightly image capture). NEVER in
    # class2Volumes — class 4 is never wiped. Approved by Robie 2026-07-16.
    volumes = [{
      image      = "git-repos.img";
      mountPoint = "/var/lib/git";
      size       = 10240;             # 10 GiB
      fsType     = "ext4";
      autoCreate = true;
    }];

    interfaces = [{
      type = "tap";
      id   = "vm-git";
      inherit mac;
    }];
  };

  # ── Guest networking: static .20.58 on VLAN 20, matched by MAC ────────────────
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = mac;
    address = [ "192.168.20.58/24" ];
    routes  = [ { Gateway = "192.168.20.254"; } ];
  };
  networking.nameservers = [ "192.168.20.254" ];   # gateway-only (Robie policy 2026-07-21); no 1.1.1.1
  services.resolved.enable = false;   # not serving DNS, but keep guests uniform (dns2 precedent)

  # ── The git service ───────────────────────────────────────────────────────────
  environment.systemPackages = [ pkgs.git ];

  # ── PINNED uid/gid (2026-07-21, Opus 4.8) — MANDATORY, not cosmetic ───────────
  # This guest has a tmpfs /etc (regenerated every boot) and does NOT persist
  # /var/lib/nixos, so an unpinned system user's auto-allocated UID DRIFTS whenever
  # the declared-user set changes. git OWNS the persistent class-4 repo volume, so a
  # drift orphans every repo (owner-uid ≠ git's new uid → "dubious ownership", writes
  # denied). This actually happened 2026-07-21: before git-daemon, git auto-allocated
  # to 999; enabling the git-daemon module (which statically pins git = ids.uids.git =
  # 41) shifted it to 41, orphaning every 999-owned repo and breaking the whole host.
  # 41 is a RESERVED static NixOS id (stable across rebuilds, no collision), so we
  # adopt it EXPLICITLY here (mkForce agrees with the module, but makes the pin
  # visible + independent — the pin must not silently depend on the daemon staying on).
  # RULE (Robie 2026-07-21): pin the uid/gid of ANY user owning a persistent volume on
  # a tmpfs-/etc guest; stateless users may drift harmlessly. See [[hypervisor-impermanence]].
  users.groups.git = { gid = lib.mkForce 41; };
  users.users.git = {
    isSystemUser = true;
    uid          = lib.mkForce 41;
    group        = "git";
    home         = "/var/lib/git";
    createHome   = false;             # the volume mounts there
    # bash so that the per-key forced commands below can run at all (see adminGitShell).
    # Neither key reaches this shell directly; each is pinned to a wrapper.
    shell        = "${pkgs.bashInteractive}/bin/bash";
    openssh.authorizedKeys.keys = [
      # robie@flipper (same key as the fleet admin recipient) — git-shell, all repos.
      "restrict,command=\"${adminGitShell}\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC/F5DsOqJb2KM0JGV3Tx6kYVYOxR0xXGuJOyu/benFU"
      # patch-automation robot (patch-deploy-key.age, held by vhost1/vhost2). Confined by
      # forced command to nixos-config.git — it cannot read or write ledger2 or work.
      "restrict,command=\"${patchRobotGitShell}\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGhQykaMU71LttS0sg17qhEgKzLF5WkVr7khRYiaeYmi"
      # NAS mirror job on vhost1 (git-mirror-key.age). Read-only by forced command:
      # upload-pack + list-repos, no receive-pack. Added 2026-08-27.
      "restrict,command=\"${gitMirrorShell}\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMY+/lkPzE/cSeWiBb12MWd6SXefhRstatZJdfJFur1B"
    ];
  };

  # Volume mounts root-owned; hand the tree to git before repo init.
  systemd.tmpfiles.rules = [ "d /var/lib/git 0750 git git -" ];

  # Self-healing ownership: chown the whole repo tree to git before init/daemon.
  # Idempotent + cheap (only touches mismatches). Repairs pre-pin 999-owned files
  # once, and re-owns anything restored from a NAS image with foreign uids — the
  # chaos-monkey guarantee that a reprovisioned volume always belongs to git.
  systemd.services.git-chown-repos = {
    description = "Ensure /var/lib/git is owned by git (uid-drift / restore repair)";
    wantedBy = [ "multi-user.target" ];
    after    = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
    before   = [ "git-init-repos.service" "git-daemon.service" ];
    serviceConfig = { Type = "oneshot"; User = "root"; };
    script = "chown -R git:git /var/lib/git";
  };

  # Idempotent bare-repo creation for the declared list (create-only, never delete).
  systemd.services.git-init-repos = {
    description = "Create declared bare git repositories";
    wantedBy = [ "multi-user.target" ];
    after    = [ "local-fs.target" "systemd-tmpfiles-setup.service" "git-chown-repos.service" ];
    requires = [ "git-chown-repos.service" ];
    serviceConfig = { Type = "oneshot"; User = "git"; Group = "git"; };
    path = [ pkgs.git ];
    script = ''
      set -eu
      cd /var/lib/git
      for r in ${lib.escapeShellArgs repos}; do
        [ -d "$r.git" ] || git init --bare --initial-branch=main "$r.git"
      done
      # Anonymous read-only git:// export — pages-content ONLY (it is the flake
      # input the unattended patch robot fetches; content is already public-on-LAN
      # over HTTP/80, so anonymous git read adds no exposure). Every other repo
      # stays ssh-key-only: git-daemon runs with exportAll=false, so a repo is
      # served over git:// only if it carries this marker. 2026-07-21 (Opus 4.8).
      touch /var/lib/git/pages-content.git/git-daemon-export-ok
    '';
  };

  # ── Self-healing HEAD repair (2026-08-27, Opus 5) ────────────────────────────
  #
  # `git init --bare --initial-branch=main` points HEAD at refs/heads/main BEFORE
  # any push. If the first push then comes from a local `master`, git creates
  # refs/heads/master alongside and HEAD is left naming a ref that DOES NOT EXIST.
  # Nothing errors. Pushes and fetches work forever. What breaks is `clone`: a bare
  # repo with a dangling HEAD stops advertising HEAD at all, so a fresh clone has no
  # default branch and lands the caller in an EMPTY working tree. That is a
  # rehydration failure visible only on the day you need to rehydrate.
  #
  # Found on four repos 2026-08-27; three were fixed by renaming, `teacha` could not
  # be (it has a GitHub origin, so the rename is a bigger job Robie deferred). This
  # repairs HEAD *without* renaming anything — the two were never the same job.
  # Idempotent and self-healing, same shape as git-chown-repos: it also re-repairs a
  # volume restored from a NAS image.
  #
  # An EMPTY repo legitimately has HEAD -> refs/heads/main with no branches. That is
  # not a fault and must not be "fixed"; the no-branches path leaves it alone.
  systemd.services.git-repair-heads = {
    description = "Repair bare repos whose HEAD names a nonexistent ref";
    wantedBy = [ "multi-user.target" ];
    after    = [ "git-init-repos.service" ];
    requires = [ "git-init-repos.service" ];
    before   = [ "git-daemon.service" ];
    serviceConfig = { Type = "oneshot"; User = "git"; Group = "git"; };
    path = [ pkgs.git ];
    script = ''
      set -eu
      cd /var/lib/git
      for d in *.git; do
        [ -d "$d" ] || continue
        target=$(git --git-dir="$d" symbolic-ref HEAD 2>/dev/null || true)
        if [ -n "$target" ] && git --git-dir="$d" show-ref --verify --quiet "$target"; then
          continue
        fi
        new=""
        for c in refs/heads/main refs/heads/master; do
          if git --git-dir="$d" show-ref --verify --quiet "$c"; then new="$c"; break; fi
        done
        if [ -z "$new" ]; then
          new=$(git --git-dir="$d" for-each-ref --format='%(refname)' --count=1 refs/heads/ || true)
        fi
        if [ -n "$new" ]; then
          git --git-dir="$d" symbolic-ref HEAD "$new"
          echo "git-repair-heads: $d HEAD was dangling ($target) -> $new"
        else
          echo "git-repair-heads: $d has no branches yet — HEAD at $target is correct for an empty repo"
        fi
      done
    '';
  };

  # ── Bound pack-objects' memory so this guest can serve what it stores ─────────
  #
  # WHY (2026-08-27): `git clone nibbles` failed for EVERY client — the kernel
  # OOM-killed git-pack-objects inside this guest (964 MiB usable, MemAvailable
  # floor 31 MiB, packer wanting ~780 MB RSS; confirmed from observ). The repo is
  # NOT corrupt, though upload-pack reports the packer's death as "possible
  # repository corruption", which sends you looking in the wrong place.
  #
  # Cause is object SHAPE, not repo size: nibbles holds three .xtch e-reader images
  # of 292M / 256M / 191M. `teacha` is 907 MB and clones fine. With the default
  # core.bigFileThreshold of 512m, git tries to DELTA-COMPRESS those blobs, which
  # means holding them in memory; below the threshold it stores them whole and
  # streams instead. That single default is the whole failure.
  #
  # Chosen over growing the guest: this makes the server able to serve what it
  # holds, rather than making the VM big enough to survive the next larger blob.
  # (Note if RAM is ever raised anyway: NOT 2048 — QEMU hang, microvm.nix #171.)
  programs.git = {
    enable = true;
    config = {
      core.bigFileThreshold = "16m";   # above this: no delta attempt, stream it
      pack = {
        windowMemory   = "32m";        # cap the delta-search window
        deltaCacheSize = "64m";        # default 256m is a large fraction of this guest
        threads        = 1;            # 1 vcpu anyway; makes the cap per-process, not per-thread
      };
    };
  };

  # ── Anonymous read-only git-daemon (git://) for the marked repo(s) ────────────
  # Solves the unattended-fetch problem for pages-content: no ssh key to authorize,
  # no host key to trust (git:// has neither), so vhost2's phase-1 robot can fetch
  # the content input without credentials. exportAll=false keeps it to the marker.
  services.gitDaemon = {
    enable    = true;
    basePath  = "/var/lib/git";
    exportAll = false;           # serve ONLY repos with git-daemon-export-ok
    user      = "git";           # needs group-read on /var/lib/git (0750 git:git)
    group     = "git";
    # enableWritable defaults false → read-only, which is exactly the intent.
  };
  networking.firewall.allowedTCPPorts = [ 9418 ];   # git protocol

  # ── microVM boot overrides (see ./dns2.nix) ───────────────────────────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;

  # Guests do NOT embed the nixos-config git rev (per-guest restart granularity —
  # proven 2026-07-07; see ./dns2.nix).
  system.configurationRevision = lib.mkForce null;

  system.stateVersion = "25.05";
}
