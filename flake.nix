{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.input.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs; ... } @ inputs: 
  {


    nixosConfigurations.NixOS1 = nixpkgs.lib.nixosSystem {
      ./configuration.nix
    };
  };
}
