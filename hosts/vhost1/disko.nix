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
# IMPERMANENCE LAYOUT (Robie's ruling 2026-07-06, ledger hypervisor-impermanence.md):
# there is NO root subvolume on disk — `/` is tmpfs, declared in configuration.nix,
# and dies at poweroff. Only three things live on the NVMe: /boot (ESP), /nix
# (btrfs subvol, zstd), /persist (btrfs subvol — the allowlist storage; guest
# volumes get cheap snapshots HERE, which is where the btrfs rationale pays).
# Everything else is bind-mounted out of /persist at boot by the impermanence
# module (see configuration.nix) or is ephemeral on purpose.

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
                # No "@" (root) and no "@var": / is tmpfs (impermanence); /var is
                # ephemeral except the /persist binds.
                "@nix" = {
                  mountpoint   = "/nix";
                  mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                };
                "@persist" = {
                  mountpoint   = "/persist";
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
