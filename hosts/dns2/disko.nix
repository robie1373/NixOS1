# hosts/dns2/disko.nix
#
# Disk layout for dns2 VM. Proxmox virtio disk.
# 8GB allocation: NixOS store + Blocky blocklist cache + logs.
# Blocky downloads lists to memory at startup — no persistent disk needed for lists.

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
