{ inputs, self, ... }:
{
  flake.nixosConfigurations.observ = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [ ../../../hosts/observ/configuration.nix ];
  };
}
