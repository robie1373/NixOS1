# hosts/nixsrv1/disko.nix
#
# Disk layout for nixsrv1 (Intel MacBook Pro bare metal).
# NVMe SSD — verify device name before deploying: `lsblk` on the running machine.
#
# No encryption: this machine lives inside the homelab physically.
# No swap: MBP has enough RAM for the planned workloads; add a swapfile later if needed.
#
# The root partition is btrfs for its snapshot capability — useful for
# rolling back after a failed microvm or container experiment.

{ ... }:

{
  disko.devices = {
    disk.main = {
      type   = "disk";
      # TODO: Verify with `lsblk` before deploying. Intel MBP NVMe is typically nvme0n1.
      device = "/dev/nvme0n1";
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
