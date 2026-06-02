{ inputs, self, ... }:
{
  flake.nixosConfigurations.flipper = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      # Overlay: adds pkgs.qmd from the upstream qmd flake (tracked as a flake input,
      # so nix flake update keeps it current automatically).
      { nixpkgs.overlays = [ (_: _: { qmd = inputs.qmd.packages.x86_64-linux.default; }) ]; }
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
      ../../_features/remote-access.nix
      ../../_features/gaming.nix
      ../../_features/korean.nix
      ../../_features/restic.nix
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
          ../../_home/obsidian.nix
          ../../_home/bearing.nix
          ../../_home/desktop-noctalia.nix
          ../../_home/firefox.nix
          ../../_home/mpv.nix
          ../../_home/imv.nix
          ../../_home/mpd.nix
          ../../_home/nas.nix
          ../../_home/yazi.nix
          ../../_home/anki-bin.nix
          ../../_home/teacha.nix
        ];
      }
    ];
  };
}
