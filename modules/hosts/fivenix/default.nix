{ inputs, self, ... }:
{
  # fivenix uses nixpkgs-stable (25.11) — CUDA/PyTorch stack is fragile on
  # unstable. home-manager.useGlobalPkgs = true means HM inherits the stable
  # pkgs from the system, so home packages also come from stable.
  flake.nixosConfigurations.fivenix = inputs.nixpkgs-stable.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/fivenix/configuration.nix
      ../../_features/common.nix
      ../../_features/tailscale-watchdog.nix
      ../../_features/1password.nix
      ../../_features/audio.nix
      ../../_features/gaming.nix
      ../../_features/korean.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs       = true;
        home-manager.useUserPackages     = true;
        home-manager.backupFileExtension = "backup";
        home-manager.extraSpecialArgs    = { inherit self; };
        home-manager.users.robie.imports = [
          inputs.nix-index-database.homeModules.nix-index
          ../../../hosts/fivenix/home.nix
          ../../_home/common.nix
          ../../_home/1password.nix
          ../../_home/gemini-cli.nix
          ../../_home/claude.nix
          ../../_home/obsidian.nix
          ../../_home/bearing.nix
          ../../_home/firefox.nix
          ../../_home/yazi.nix
          ../../_home/mpv.nix
          ../../_home/imv.nix
          ../../_home/anki-bin.nix
        ];
      }
    ];
  };
}
