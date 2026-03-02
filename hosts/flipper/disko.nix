{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Verify the correct device before deploying: lsblk
        # Common alternatives: /dev/sda (SATA), /dev/nvme0n1 (NVMe)
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {

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

            # 16G matches the installed RAM — hibernate requires swap >= RAM
            swap = {
              size = "16G";
              content = {
                type = "swap";
              };
            };

            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-L" "nixos" "-f" ];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                };
              };
            };

          };
        };
      };
    };
  };
}
