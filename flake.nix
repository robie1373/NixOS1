{
  description = "Dry Dock. Robies DRY fleet configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager,  ... } @ inputs: 
  {
    nixosConfigurations =  {

      nixos1 = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        system = "aarch64-linux";
        modules = [
          ./hosts/nixos1/configuration.nix
          ./modules/system/1password.nix
          ./modules/system/common.nix

 
          inputs.home-manager.nixosModules.home-manager {
	    home-manager.useGlobalPkgs = true;
	    home-manager.useUserPackages = true;
            home-manager.users.robie = {
              imports = [ 
		./hosts/nixos1/home.nix
	        ./modules/home/common.nix 
                ./modules/home/1password.nix
		./modules/home/gemini-cli.nix
	        ./modules/home/claude.nix
	      ];
           };
	  }
   	];
      };



    };
  };
}
