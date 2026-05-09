{ inputs, self, ... }:
{
  flake.nixosConfigurations.dns1 = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [ ../../../hosts/dns1/configuration.nix ];
  };
}
