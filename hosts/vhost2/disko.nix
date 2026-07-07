# hosts/vhost2/disko.nix
#
# Disk layout for vhost2 (formerly pve2). Whole-disk claim — the conversion
# WIPES this SSD; there is no undo (proxmox-to-microvm.md, executor contract §3).
#
# Device: Samsung SSD 840 PRO 238.5G, confirmed /dev/sda on pve2 (lsblk 2026-07-04).
# Pinned by-id so disko can't grab the wrong disk (the 3.7G install USB is /dev/sdb).
#
# IMPERMANENCE RETROFIT LAYOUT (Robie's ruling 2026-07-06, ledger
# hypervisor-impermanence.md — this branch deploys at the retrofit window ONLY):
# no root/@var subvolume — / is tmpfs (configuration.nix); only /boot, @nix and
# @persist live on disk. Guest volumes sit under the persisted+snapshottable
# @persist. ⚠️ DO NOT merge to main outside the retrofit window: a routine
# switch+reboot on the OLD disk layout with THIS config = unbootable (no
# @persist subvolume exists until nixos-anywhere re-runs disko).

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
            # Pinned partition GUID: firmware boot entries reference the ESP by
            # its GPT partition UUID. A reinstall that regenerates the GUID
            # invalidates the entry and the BIOS boot-priority pin silently
            # falls back to the legacy device entry — the machine then needs a
            # human at the console (bit us 2026-07-05 AND 2026-07-07). A stable
            # GUID keeps the firmware entry (and the pinned priority) valid
            # across reinstalls — self-healing by construction.
            uuid = "471b697e-dc75-485c-a24f-2666bcedef21";
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
