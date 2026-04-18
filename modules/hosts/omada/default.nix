{ inputs, self, ... }:
{
  flake.nixosConfigurations.omada = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/omada/configuration.nix
    ];
  };
}
