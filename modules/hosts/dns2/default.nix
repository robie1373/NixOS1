{ inputs, self, ... }:
{
  flake.nixosConfigurations.dns2 = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [ ../../../hosts/dns2/configuration.nix ];
  };
}
