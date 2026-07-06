# hosts/vhost1/disko.nix
#
# Disk layout for vhost1 (formerly pve). Whole-disk claim — the conversion WIPES
# this disk; there is no undo (proxmox-to-microvm.md, executor contract §3).
#
# Device: the 1 TB NVMe ONLY — Samsung 970 EVO Plus 1TB, pinned by-id so disko
# CANNOT touch the other disk. pve has a SECOND disk, the 2 TB Samsung 870 EVO
# SATA (/dev/sda, label "Data", ollama + timeshift). Robie's decision 2026-07-05:
# leave the SATA entirely alone — it is not part of vhost1 and disko must never
# reference it. Pinning `device` to the NVMe by-id guarantees that.
#
# btrfs root with zstd — same rationale as vhost2/nixsrv1: cheap snapshots to roll
# back a failed microvm/host experiment, compression stretches the disk, and the
# /nix/store is shared read-only into every guest (D8). 1 TB is ample for the host
# store + every guest state volume (langlab 16G, observ 20G, the rest tiny).

{ ... }:

{
  disko.devices = {
    disk.main = {
      type   = "disk";
      # NVMe boot disk ONLY. The 2 TB SATA (ata-Samsung_SSD_870_EVO_2TB_S6PNNJ0W303102W)
      # is deliberately absent — untouched by the conversion.
      device = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_1TB_S59ANMFN932546Z";
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
