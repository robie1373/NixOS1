{ inputs, ... }:
{
  flake.nixosConfigurations.langlab = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules     = [
      ../../../hosts/langlab/configuration.nix
    ];
  };
}
