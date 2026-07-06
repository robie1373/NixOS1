# hosts/vhost2/guests/bproof.nix
#
# THROWAWAY test guest (rung-5 B-mechanism proof, 2026-07-06). Proves that a
# microVM can carry a STABLE SSH host key on its persistent volume and that
# in-guest agenix decrypts a secret keyed to that persisted key. Delete after.
#
# No network — it reports results to the host via a writable virtiofs share.

{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    ../../../modules/_system/server-common.nix   # same base the real guests use (agenix, sshd)
  ];

  networking.hostName = "bproof";

  microvm = {
    hypervisor = "qemu";
    vcpu = 1;
    mem  = 1024;
    # Persistent state volume — the SSH host key lives here (the mechanism).
    volumes = [{
      image      = "persist.img";
      mountPoint = "/var/lib/persist";
      size       = 128;
      fsType     = "ext4";
      autoCreate = true;
    }];
    shares = [
      { source = "/nix/store";        mountPoint = "/nix/.ro-store"; tag = "ro-store";   proto = "virtiofs"; }
      # Writable share so the guest can write its report where the host reads it.
      { source = "/var/lib/bproof-out"; mountPoint = "/srv/out";     tag = "bproof-out"; proto = "virtiofs"; }
    ];
    # No interfaces on purpose — this test needs no network.
  };

  # ── MECHANISM UNDER TEST ────────────────────────────────────────────────────
  # sshd host key on the persistent volume (override server-common's /etc/ssh path).
  services.openssh.hostKeys = lib.mkForce [{
    path = "/var/lib/persist/ssh_host_ed25519_key";
    type = "ed25519";
  }];
  # agenix uses that persisted key as its ONLY identity.
  age.identityPaths = lib.mkForce [ "/var/lib/persist/ssh_host_ed25519_key" ];
  age.secrets.testsecret.file = ../../../secrets/testsecret.age;

  # Report pubkey + decrypted secret to the host share.
  systemd.services.bproof-report = {
    wantedBy = [ "multi-user.target" ];
    after    = [ "sshd.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      mkdir -p /srv/out
      {
        echo "PUBKEY: $(cat /var/lib/persist/ssh_host_ed25519_key.pub 2>/dev/null || echo MISSING)"
        echo "AGENIX: $(cat /run/agenix/testsecret 2>/dev/null || echo NODECRYPT)"
        echo "BOOT_ID: $(cat /proc/sys/kernel/random/boot_id)"
      } > /srv/out/report.txt
    '';
  };

  # microVM boot overrides + drop server-common baggage irrelevant to the test.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;

  system.stateVersion = "25.05";
}
