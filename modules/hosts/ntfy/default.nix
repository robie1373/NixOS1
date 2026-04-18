{ inputs, self, ... }:
{
  flake.nixosConfigurations.ntfy = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/ntfy/configuration.nix
    ];
  };
}
