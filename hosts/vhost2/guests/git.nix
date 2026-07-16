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
    "test"           # probation/scratch repo (new-service protocol B3/B4)
  ];
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
  networking.nameservers = [ "192.168.20.254" "1.1.1.1" ];
  services.resolved.enable = false;   # not serving DNS, but keep guests uniform (dns2 precedent)

  # ── The git service ───────────────────────────────────────────────────────────
  environment.systemPackages = [ pkgs.git ];

  users.groups.git = {};
  users.users.git = {
    isSystemUser = true;
    group        = "git";
    home         = "/var/lib/git";
    createHome   = false;             # the volume mounts there
    shell        = "${pkgs.git}/bin/git-shell";   # push/pull only — no interactive login
    openssh.authorizedKeys.keys = [
      # robie@flipper (same key as the fleet admin recipient)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC/F5DsOqJb2KM0JGV3Tx6kYVYOxR0xXGuJOyu/benFU"
    ];
  };

  # Volume mounts root-owned; hand the tree to git before repo init.
  systemd.tmpfiles.rules = [ "d /var/lib/git 0750 git git -" ];

  # Idempotent bare-repo creation for the declared list (create-only, never delete).
  systemd.services.git-init-repos = {
    description = "Create declared bare git repositories";
    wantedBy = [ "multi-user.target" ];
    after    = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
    serviceConfig = { Type = "oneshot"; User = "git"; Group = "git"; };
    path = [ pkgs.git ];
    script = ''
      set -eu
      cd /var/lib/git
      for r in ${lib.escapeShellArgs repos}; do
        [ -d "$r.git" ] || git init --bare --initial-branch=main "$r.git"
      done
    '';
  };

  # ── microVM boot overrides (see ./dns2.nix) ───────────────────────────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;

  # Guests do NOT embed the nixos-config git rev (per-guest restart granularity —
  # proven 2026-07-07; see ./dns2.nix).
  system.configurationRevision = lib.mkForce null;

  system.stateVersion = "25.05";
}
