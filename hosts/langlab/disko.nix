# hosts/langlab/disko.nix
#
# Disk layout for LangLab VM. Simple two-partition layout.
# 16 GB total — larger than ntfy to accommodate audio files (MP3s, VTTs).

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
