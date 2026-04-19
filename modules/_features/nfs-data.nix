# modules/_features/nfs-data.nix
#
# Lazy NFS automount for the NAS data share (192.168.20.12:/data).
# Mounts at ~/nas on first access; unmounts after 10 min idle.
# No boot-time mount — does not hang if the NAS is down.
#
# hard mount: if the NAS becomes unreachable while a file is open,
# the accessing process blocks until the server returns. This prevents
# data corruption (the safe NFS default).

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
      "x-systemd.automount"       # mount on first access, not at boot
      "noauto"                    # suppresses the implicit boot-time mount unit
      "x-systemd.idle-timeout=600" # unmount after 10 min idle
      "nfsvers=4.1"
      "hard"                      # block on server loss rather than error (prevents corruption)
      "noatime"
    ];
  };
}
