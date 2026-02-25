{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, ... } @ inputs: 
  {


    nixosConfigurations.nixos1 = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      system = "aarch64-linux";
      modules = [
        ./hosts/workstation/configuration.nix
	inputs.home-manager.nixosModules.home-manager {
	  home-manager.users.robie = {
	    imports = [ ./modules/home/common.nix ];
	  };
	}
      ];
    };
  };
}
