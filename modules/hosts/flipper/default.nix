{ inputs, self, ... }:
{
  flake.nixosConfigurations.flipper = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/flipper/configuration.nix
      ../../_system/common.nix
      ../../_system/1password.nix
      ../../_system/audio.nix
      ../../_system/desktop-hyprland.nix
      ../../_system/nas.nix
      ../../_system/speaker-fix.nix
      inputs.disko.nixosModules.disko
      ../../../hosts/flipper/disko.nix
      ../../_system/gaming.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs         = true;
        home-manager.useUserPackages       = true;
        home-manager.backupFileExtension   = "backup";
        home-manager.extraSpecialArgs      = { inherit self; };
        home-manager.users.robie.imports   = [
          inputs.nix-index-database.hmModules.nix-index
          ../../../hosts/flipper/home.nix
          ../../_home/common.nix
          ../../_home/1password.nix
          ../../_home/gemini-cli.nix
          ../../_home/claude.nix
          ../../_home/obsidian.nix
          ../../_home/bearing.nix
          ../../_home/desktop-hyprland.nix
          ../../_home/firefox.nix
          ../../_home/tablet.nix
          ../../_home/mpv.nix
          ../../_home/imv.nix
          ../../_home/mpd.nix
          ../../_home/nas.nix
          ../../_home/yazi.nix
          ../../_home/hyprshot.nix
          ../../_home/anki-bin.nix
        ];
      }
    ];
  };
}
