# modules/_features/nfs-data.nix
#
# Lazy NFS automount for the NAS data share (192.168.20.12:/data).
# Mounts at ~/nas on first access; unmounts after 10 min idle.
# No boot-time mount — does not hang if the NAS is down.
#
# soft mount: if the NAS becomes unreachable, return I/O error to the
# caller after timeo/retrans attempts rather than blocking indefinitely.
# With hard+noauto, systemd daemon-reload hung for 90s during nh os switch
# when TrueNAS was down (2026-05-10). Soft is the right tradeoff for a
# personal NAS used for file storage — data corruption risk is low.

{ config, ... }:
{
  # NFSv4 kernel module support — no rpcbind needed, uses TCP 2049 directly.
  boot.supportedFilesystems = [ "nfs" ];

  # Create mount point in user home before any mount units activate.
  systemd.tmpfiles.rules = [
    "d /home/robie/nas 0755 robie users -"
  ];

  fileSystems."/home/robie/nas" = {
    device = "192.168.20.12:/mnt/tank/data";
    fsType = "nfs";
    options = [
      "x-systemd.automount"        # mount on first access, not at boot
      "noauto"                     # suppresses the implicit boot-time mount unit
      "x-systemd.idle-timeout=600" # unmount after 10 min idle
      "x-systemd.mount-timeout=10" # systemd gives up mounting after 10s
      "nfsvers=4.1"
      "soft"                       # return I/O error on server loss rather than blocking
      "timeo=30"                   # 3s per RPC attempt before retry
      "retrans=2"                  # 2 retries before failing
      "noatime"
    ];
  };

  # Clear the mount's failed state after a transient miss (2026-08-08).
  #
  # Activation restarts NetworkManager, which deauthenticates wlo1 for ~14s,
  # and this share lives on VLAN 20 — reachable only over wifi. Anything that
  # touches ~/nas in that window (yazi, rg, any filesystem walker) fires the
  # automount, mount.nfs returns ENETUNREACH, and the .mount unit parks in
  # `failed`. The mount itself is self-healing: the .automount stays armed and
  # the next access succeeds.
  #
  # The damage is to the *switch*, not the mount. switch-to-configuration scans
  # every unit on the system at the end of activation and exits 4 if any is
  # failed; `nh os switch` treats that as fatal and never registers the
  # generation, so the machine silently reverts on reboot. Clearing the state
  # keeps a benign automount miss out of that scan.
  #
  # Tradeoff: a genuinely-down NAS also stops appearing in switch output. That's
  # correct — an on-demand automount being unavailable is not a config failure.
  # No restart loop: reset-failed does not re-trigger the mount.
  systemd.units."home-robie-nas.mount" = {
    overrideStrategy = "asDropin";
    text = ''
      [Unit]
      OnFailure=nas-mount-reset-failed.service
    '';
  };

  systemd.services.nas-mount-reset-failed = {
    description = "Clear the transient failed state of home-robie-nas.mount";
    serviceConfig = {
      Type = "oneshot";
      # config.systemd.package, not pkgs.systemd — the latter is a different
      # store path from the system's systemd and pulls a second build into the
      # closure.
      ExecStart = "${config.systemd.package}/bin/systemctl reset-failed home-robie-nas.mount";
    };
  };
}
