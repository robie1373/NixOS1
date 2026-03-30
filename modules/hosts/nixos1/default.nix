{ inputs, self, ... }:
{
  flake.nixosConfigurations.nixos1 = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/nixos1/configuration.nix
      ../../_system/common.nix
      ../../_system/1password.nix
      ../../_system/audio.nix
      ../../_system/desktop-hyprland.nix
      ../../_system/vm-guest.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs         = true;
        home-manager.useUserPackages       = true;
        home-manager.backupFileExtension   = "backup";
        home-manager.users.robie.imports   = [
          inputs.nix-index-database.hmModules.nix-index
          ../../../hosts/nixos1/home.nix
          ../../_home/common.nix
          ../../_home/1password.nix
          ../../_home/gemini-cli.nix
          ../../_home/claude.nix
          ../../_home/obsidian.nix
          ../../_home/bearing.nix
          ../../_home/desktop-hyprland.nix
          ../../_home/firefox.nix
          ../../_home/yazi.nix
          ../../_home/hyprshot.nix
        ];
      }
    ];
  };
}
