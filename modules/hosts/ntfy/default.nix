{ inputs, ... }:
{
  flake.nixosConfigurations.ntfy = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      ../../../hosts/ntfy/configuration.nix
    ];
  };
}
