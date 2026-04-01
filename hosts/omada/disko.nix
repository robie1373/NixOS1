# hosts/omada/disko.nix
#
# Disk layout for the Omada controller VM.
# Simple two-partition layout — no encryption, no swap.
#
# Omada bundles MongoDB and stores AP firmware images under
# /var/lib/omada-controller/. 16 GB gives headroom for firmware
# images for two EAP773s plus historical client data.

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
