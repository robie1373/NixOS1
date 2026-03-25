# hosts/ntfy/disko.nix
#
# Disk layout for the ntfy VM. Simple two-partition layout — no encryption,
# no swap. ntfy is a single Go binary with a SQLite cache; it has no need
# for exotic disk arrangements.
#
# Power-loss resilience is handled at the application layer:
#   - ntfy cache-file (SQLite WAL) survives hard power loss without corruption
#   - Clients reconnect and replay missed messages via the since= parameter
#
# If UPS integration is added later and hibernate becomes desirable for planned
# maintenance, add a swap partition >= RAM size at that time.

{ ... }:

{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/vda";  # virtio disk — standard for Proxmox KVM VMs
      content = {
        type = "gpt";
        partitions = {

          # EFI System Partition — required for systemd-boot
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          # Root partition — remainder of disk
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };

        };
      };
    };
  };
}
