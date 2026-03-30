{ inputs, self, ... }:
{
  flake.nixosConfigurations.nixos1 = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/nixos1/configuration.nix
      ../../_features/common.nix
      ../../_features/1password.nix
      ../../_features/audio.nix
      ../../_features/desktop-hyprland.nix
      ../../_features/vm-guest.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs         = true;
        home-manager.useUserPackages       = true;
        home-manager.backupFileExtension   = "backup";
        home-manager.extraSpecialArgs      = { inherit self; };
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
