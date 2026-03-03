{ inputs, ... }:
let
  mkHost = { system, modules }: inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs; };
    inherit system modules;
  };
in
{
  flake.nixosConfigurations = {
    
    nixos1 = mkHost {
      system = "aarch64-linux";
      modules = [
        ../hosts/nixos1/configuration.nix
        ../modules/system/common.nix
        ../modules/system/1password.nix
        ../modules/system/audio.nix
        #../modules/system/desktop-kde.nix
	../modules/system/desktop-hyprland.nix
        ../modules/system/vm-guest.nix
       # inputs.disko.nixosModules.disko
       # ../hosts/flipper/disko.nix
        inputs.home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.robie.imports = [
            ../hosts/nixos1/home.nix
            ../modules/home/common.nix
            ../modules/home/1password.nix
            ../modules/home/gemini-cli.nix
            ../modules/home/claude.nix
	    ../modules/home/obsidian.nix
	    ../modules/home/desktop-hyprland.nix
	    ../modules/home/firefox.nix
	    ../modules/home/entertainment.nix
          ];
	}
      ];
    };

    flipper = mkHost {
      system = "x86_64-linux";
      modules = [
        ../hosts/flipper/configuration.nix
        ../modules/system/common.nix
        ../modules/system/1password.nix
        ../modules/system/audio.nix
        #../modules/system/desktop-kde.nix
        ../modules/system/desktop-hyprland.nix
        inputs.disko.nixosModules.disko
        ../hosts/flipper/disko.nix
        inputs.home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.robie.imports = [
            ../hosts/flipper/home.nix
            ../modules/home/common.nix
            ../modules/home/1password.nix
            ../modules/home/gemini-cli.nix
            ../modules/home/claude.nix
            ../modules/home/obsidian.nix
            ../modules/home/desktop-hyprland.nix
            ../modules/home/firefox.nix
            ../modules/home/tablet.nix
          ];
        }
      ];
    };

#    nixos2 = mkHost {
#      system = "x86_64-linux";
#      modules = [
#        ../hosts/nixos1/configuration.nix
#        ../modules/system/common.nix
#        ../modules/system/1password.nix
#        ../modules/system/audio.nix
#        ../modules/system/desktop-kde.nix
#        inputs.home-manager.nixosModules.home-manager {
#          home-manager.useGlobalPkgs = true;
#          home-manager.useUserPackages = true;
#          home-manager.users.robie.imports = [
#            ../hosts/nixos2/home.nix
#            ../modules/home/common.nix
#            ../modules/home/1password.nix
#          ];
#	}
#      ];
#    };
#
#    major-ant = mkHost {
#      system = "x86_64-linux";
#      modules = [
#        ../hosts/major-ant/configuration.nix
#        ../modules/system/common.nix
#        ../modules/system/1password.nix
#        ../modules/system/audio.nix
#        ../modules/system/desktop-kde.nix
#        ../modules/system/vm-guest.nix
#        inputs.home-manager.nixosModules.home-manager {
#          home-manager.useGlobalPkgs = true;
#          home-manager.useUserPackages = true;
#          home-manager.users.robie.imports = [
#            ../hosts/major-ant/home.nix
#            ../modules/home/common.nix
#            ../modules/home/1password.nix
#          ];
#	}
#      ];
#    };



  };
}
