{ inputs, self, ... }:
{
  flake.nixosConfigurations.fivenix = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/fivenix/configuration.nix
      ../../_features/common.nix
      ../../_features/tailscale-watchdog.nix
      ../../_features/1password.nix
      ../../_features/audio.nix
      ../../_features/nfs-data.nix
      ../../_features/gaming.nix
      ../../_features/korean.nix
      ../../_features/restic.nix
      # bearing: moved from _home/ to _features/ in Phase 3.7 Tier 1; disabled on fivenix
      ../../_features/bearing.nix
    ];
  };
}
