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
  # NOTE: Omada's scheduled auto-backup is a controller UI setting (not settable
  # via the mbentley image) — enable it once post-standup: Settings → Maintenance →
  # Backup & Restore → Auto Backup (schedule + retention). Until then this dir is
  # simply empty; the .cfg export is also the manual restore vehicle (spec step 1/5).
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

  system.stateVersion = "25.05";

  # ── Backups: option (b), host-side — chosen 2026-07-05 ────────────────────────
  # Robie chose host-side backup over in-guest restic (keeps the guest key-less;
  # D10 stays clean). This guest's only job for backups is the writable autobackup
  # share above; the actual restic job runs on the vhost2 HOST (see
  # ../configuration.nix) against /var/lib/omada-backups using vhost2's OWN key —
  # no host key is planted in this microVM.
  #
  # OPEN (needs Robie): the host restic job needs credentials
  # (restic-backup-vhost2 / restic-repo-password-vhost2 age secrets). Reusing
  # omada's existing repo by re-encrypting its secrets to vhost2 got fussy (age
  # couldn't decrypt with the admin key), so that's parked; the clean path is fresh
  # creds the documented way (op write + NAS authorized_keys — both Robie-gated).
  # Until the secrets exist, the host restic wiring is held out (agenix would fail
  # to build referencing missing .age files).
}
