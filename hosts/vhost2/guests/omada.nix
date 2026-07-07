# hosts/vhost2/guests/omada.nix
#
# omada — TP-Link Omada SDN controller, as a microVM guest of vhost2.
# all-nixos-lab rung 4 / Phase B2 step 5, guest 3/3. Unlike dns2/pages this guest
# is STATEFUL (D1 exception): the controller's MongoDB DB must survive the
# conversion. Runs Docker (mbentley/omada-controller) with host networking.
#
# STATE MODEL (D8): a writable block volume (raw image on the host, under the
# guest's stateDir /var/lib/microvms/omada/) mounted at /var/lib — this persists
# BOTH the Omada data dir (/var/lib/omada-controller) AND the Docker image/graph
# (/var/lib/docker), so the ~hundreds-of-MB controller image is not re-pulled on
# every boot. MongoDB is deliberately on a block volume, NOT a virtiofs share —
# databases on 9p/virtiofs are a known consistency hazard (ledger: DB-on-NFS pain).
#
# ⚠️ restic is NOT enabled here yet. The old omada VM ran restic.nix in-guest, but
# restic.nix decrypts agenix secrets with omada's PRIVATE host key, and planting a
# host key into a microVM is an unproven mechanism in this fleet (hosts are stateless
# by design, D10). That decision is pending Robie — see the note at the bottom and
# ledger proxmox-to-microvm.md Phase B2. The conversion is covered by the Omada-UI
# settings backup (spec Phase B2 step 1) regardless.
#
# Passed to the host as `microvm.vms.omada.config`. See ../configuration.nix.

{ inputs, config, lib, pkgs, ... }:

let
  # Locally-administered MAC. Mnemonic: VLAN 20, host octet 50.
  mac = "02:00:00:00:20:50";
in
{
  imports = [
    ../../../modules/_system/server-common.nix       # ssh, agenix, observability agent, nix pinning
    ../../../modules/_system/omada-controller.nix     # Docker + controller container
  ];

  networking.hostName = "omada";

  # ── microVM runtime ──────────────────────────────────────────────────────────
  microvm = {
    hypervisor = "qemu";              # D4
    vcpu = 2;
    mem  = 3072;                      # matches the old 3 GB VM

    # D8 — shared read-only host store; plus a WRITABLE share for Omada's own
    # scheduled .cfg auto-backups so they land on vhost2's real filesystem, where
    # the HOST backs them up (option b). Only the small static .cfg exports go over
    # virtiofs — the live MongoDB stays on the block volume above (share is safe for
    # the exports, unsafe for the DB). Host share source /var/lib/omada-backups is
    # auto-created by the microvm host module (tmpfiles, microvm:kvm 0775).
    shares = [
      {
        source     = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag        = "ro-store";
        proto      = "virtiofs";
      }
      {
        source     = "/var/lib/omada-backups";
        mountPoint = "/srv/omada-autobackup";
        tag        = "omada-autobackup";
        proto      = "virtiofs";
        # writable (readOnly defaults false)
      }
    ];

    # Stateful block volume for /var/lib (Omada data + Docker graph). Raw image
    # auto-created in the guest's stateDir on the host; ext4.
    volumes = [{
      image      = "omada-var.img";
      mountPoint = "/var/lib";
      size       = 16384;             # 16 GiB — MongoDB + controller image + logs
      fsType     = "ext4";
      autoCreate = true;
    }];

    interfaces = [{
      type = "tap";
      id   = "vm-omada";
      inherit mac;
    }];
  };

  # ── Guest networking: static .20.50 on VLAN 20, matched by MAC ────────────────
  # This IP MUST NOT change — APs/switch are configured to reach the controller here.
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = mac;
    address = [ "192.168.20.50/24" ];
    routes  = [ { Gateway = "192.168.20.254"; } ];
  };
  networking.nameservers = [ "192.168.20.254" "1.1.1.1" ];

  # ── The controller ────────────────────────────────────────────────────────────
  mySystem.omada-controller.enable = true;

  # Bind the writable autobackup share over the container's autobackup subdir, so
  # Omada's scheduled .cfg exports are written straight onto the host share (which
  # vhost2 backs up). Concatenates with the volume list in omada-controller.nix.
  # Path VERIFIED 2026-07-05 (Opus 4.8) from the controller's bin/control.sh:
  #   AUTOBACKUP_DIR="${DATA_DIR}/autobackup" → /opt/tplink/EAPController/data/autobackup.
  # Auto Backup itself is a controller UI setting (enabled on the old controller
  # 2026-07-05; it should ride the .cfg restore — verify at standup, spec B2 step 5).
  # ⚠️ Write-perm caveat: Omada runs as uid 508; the share source is microvm:kvm 0775,
  # so 508 = "other" = no write. If the first backup doesn't land in the share, grant
  # 508 write on /var/lib/omada-backups (host tmpfiles) — verify at standup.
  virtualisation.oci-containers.containers.omada-controller.volumes = [
    "/srv/omada-autobackup:/opt/tplink/EAPController/data/autobackup"
  ];

  # Force /etc/hosts so the LAN IP is the ONLY resolution for "omada" — otherwise
  # NixOS's auto 127.0.0.2 entry makes the controller advertise a loopback inform
  # URL that APs/switches can't reach. (Carried verbatim from the old omada host.)
  environment.etc."hosts".text = lib.mkForce ''
    127.0.0.1 localhost
    ::1 localhost
    192.168.20.50 omada
  '';

  # ── microVM boot overrides (see ./dns2.nix) ───────────────────────────────────
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;

  # Guests do NOT embed the nixos-config git rev (server-common sets it from
  # inputs.self.rev). With it, EVERY commit changes every guest closure and a
  # host switch restarts all guests — defeating per-guest restart granularity
  # (proven 2026-07-07). Hosts keep theirs; guests are identity-less anyway.
  system.configurationRevision = lib.mkForce null;

  system.stateVersion = "25.05";

  # ── Backups: option (b), host-side ────────────────────────────────────────────
  # Host-side backup keeps this guest key-less (D10 stays clean). The guest's only
  # job is the writable autobackup share above; the restic job itself runs on the
  # vhost2 HOST — a per-guest set `mySystem.restic.backups.omada` in
  # ../configuration.nix, backing up /var/lib/omada-backups with vhost2's own key.
  # Credentials are vhost2-scoped re-encryptions of omada's, so it reuses omada's
  # NAS repo (history preserved). See the multi-set restic.nix.
  #
  # One manual step remains: enable Omada's scheduled auto-backup in the controller
  # UI post-standup so the .cfg exports actually flow into the share.
}
