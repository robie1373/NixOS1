{ inputs, self, ... }:
{
  flake.nixosConfigurations.pages = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [ ../../../hosts/pages/configuration.nix ];
  };
}
