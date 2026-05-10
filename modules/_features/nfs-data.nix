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

{ ... }:
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
}
