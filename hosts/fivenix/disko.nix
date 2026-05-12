{
  disko.devices = {
    disk = {
      main = {
        type   = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {

            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type       = "filesystem";
                format     = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            # 36G: slightly over 32G RAM so hibernate has room for dirty pages.
            # NUT server can trigger hibernate on UPS power loss — requires swap
            # >= MemTotal. See ledger2/interests/elite-dangerous.md for NUT plan.
            swap = {
              size    = "36G";
              content = { type = "swap"; };
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
                  "@home" = {
                    mountpoint   = "/home";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@nix" = {
                    mountpoint   = "/nix";
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
