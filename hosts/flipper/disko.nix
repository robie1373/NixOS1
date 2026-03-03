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
                type = "luks";
                name = "cryptroot";
                settings = {
                  # Allow TRIM pass-through to the NVMe — safe and improves
                  # longevity; minor theoretical info leak (which sectors are
                  # free) is acceptable for a laptop threat model.
                  allowDiscards = true;
                };
                # nixos-anywhere will prompt for the initial passphrase here.
                # This becomes the recovery passphrase (slot 0).
                # After first boot, enroll TPM2+PIN and YubiKey 5C:
                #   systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes /dev/nvme0n1p3
                #   systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p3
                # Store the recovery passphrase in 1Password before wiping the old install.
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
  };
}
