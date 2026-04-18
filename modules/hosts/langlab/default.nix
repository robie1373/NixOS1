{ inputs, self, ... }:
{
  flake.nixosConfigurations.langlab = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [
      ../../../hosts/langlab/configuration.nix
    ];
  };
}
