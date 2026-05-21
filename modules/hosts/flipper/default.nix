{ inputs, self, ... }:
{
  flake.nixosConfigurations.flipper = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/flipper/configuration.nix
      ../../_features/common.nix
      ../../_features/tailscale-watchdog.nix
      ../../_features/1password.nix
      ../../_features/audio.nix
      ../../_features/desktop-niri.nix
      ../../_features/desktop-noctalia.nix
      ../../_features/greeter-regreet.nix
      #../../_features/desktop-kde.nix
      ../../_features/nas.nix
      ../../_features/nfs-data.nix
      ../../_features/speaker-fix.nix
      inputs.disko.nixosModules.disko
      ../../../hosts/flipper/disko.nix
      ../../_features/gaming.nix
      ../../_features/korean.nix
      ../../_features/restic.nix
      ../../_features/bearing.nix
      ../../_features/teacha.nix
      {
        bearing = {
          enable      = true;
          terminal    = "foot";
          ntfy.server = "https://ntfy.vimba-stairs.ts.net";
        };
        teacha = {
          enable      = false;
          package     = inputs.teacha.packages.x86_64-linux.teacha-daemon;
          pollSeconds = 120;
        };
      }
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs         = true;
        home-manager.useUserPackages       = true;
        home-manager.backupFileExtension   = "backup";
        home-manager.extraSpecialArgs      = { inherit self inputs; };
        home-manager.users.robie.imports   = [
          inputs.nix-index-database.homeModules.nix-index
          ../../../hosts/flipper/home.nix
          ../../_home/common.nix
          ../../_home/gemini-cli.nix
          ../../_home/claude.nix
          ../../_home/desktop-noctalia.nix
          ../../_home/firefox.nix
          ../../_home/mpv.nix
          ../../_home/imv.nix
          ../../_home/mpd.nix
          ../../_home/yazi.nix
        ];
      }
    ];
  };
}
