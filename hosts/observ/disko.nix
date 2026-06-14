# hosts/observ/disko.nix
#
# Disk layout for observ VM. Proxmox virtio disk (~16 GB).
# Holds NixOS store + VictoriaMetrics/VictoriaLogs data (~10 day retention).
# boot.growPartition (server-common) lets a Proxmox qm resize take effect on
# next redeploy without in-VM intervention.

{ ... }:

{
  disko.devices = {
    disk.main = {
      type   = "disk";
      device = "/dev/vda";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type         = "filesystem";
              format       = "vfat";
              mountpoint   = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size    = "100%";
            content = {
              type       = "filesystem";
              format     = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
