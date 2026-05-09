# modules/hosts/nixsrv1/default.nix
#
# nixsrv1 flake output declaration.

{ inputs, self, ... }:
{
  flake.nixosConfigurations.nixsrv1 = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [
      inputs.microvm.nixosModules.host
      ../../../hosts/nixsrv1/configuration.nix
    ];
  };
}
