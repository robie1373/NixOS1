# modules/hosts/nixsrv1/default.nix
#
# nixsrv1 flake output declaration.
#
# NOTE: This host requires the microvm flake input.
# Add to flake.nix inputs before deploying:
#
#   microvm = {
#     url = "github:astro/microvm.nix";
#     inputs.nixpkgs.follows = "nixpkgs";
#   };
#
# And pass it via specialArgs or as an extra module here.

{ inputs, self, ... }:
{
  flake.nixosConfigurations.nixsrv1 = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [
      # microvm.nix host module — provides microvm.host.enable option
      # TODO: uncomment after adding microvm input to flake.nix
      # inputs.microvm.nixosModules.host
      ../../../hosts/nixsrv1/configuration.nix
    ];
  };
}
