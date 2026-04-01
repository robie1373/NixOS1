{ inputs, ... }:
{
  flake.nixosConfigurations.omada = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      ../../../hosts/omada/configuration.nix
    ];
  };
}
