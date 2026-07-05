# hosts/vhost2/disko.nix
#
# Disk layout for vhost2 (formerly pve2). Whole-disk claim — the conversion
# WIPES this SSD; there is no undo (proxmox-to-microvm.md, executor contract §3).
#
# Device: Samsung SSD 840 PRO 238.5G, confirmed /dev/sda on pve2 (lsblk 2026-07-04).
# Pinned by-id so disko can't grab the wrong disk (the 3.7G install USB is /dev/sdb).
#
# btrfs root with zstd — same rationale as nixsrv1: cheap snapshots to roll back a
# failed microvm/host experiment, and compression stretches the 16 GB node's SSD
# while the /nix/store is shared read-only into every guest (D8).

{ ... }:

{
  disko.devices = {
    disk.main = {
      type   = "disk";
      device = "/dev/disk/by-id/ata-Samsung_SSD_840_PRO_Series_S12RNEAD337437H";
      content = {
        type = "gpt";
        partitions = {

          ESP = {
            size = "1G";                     # headroom for kernels/generations (configurationLimit 20)
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
              type      = "btrfs";
              extraArgs = [ "-L" "nixos" "-f" ];
              subvolumes = {
                "@" = {
                  mountpoint   = "/";
                  mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                };
                "@nix" = {
                  mountpoint   = "/nix";
                  mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                };
                "@var" = {
                  mountpoint   = "/var";
                  mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                };
              };
            };
          };

        };
      };
    };
  };
}
