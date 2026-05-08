{ ... }:
{
  # Noctalia binary cache — avoids building Quickshell from source (~2h on flipper).
  nix.settings = {
    extra-substituters      = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  # power-profiles-daemon: noctalia's power-mode widget requires this.
  # bluetooth and upower already enabled in hosts/flipper/configuration.nix.
  services.power-profiles-daemon.enable = true;
}
