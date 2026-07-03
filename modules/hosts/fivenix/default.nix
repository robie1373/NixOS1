{ inputs, self, ... }:
{
  flake.nixosConfigurations.fivenix = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/fivenix/configuration.nix
      ../../_features/common.nix
      ../../_features/tailscale-watchdog.nix
      ../../_features/1password.nix
      ../../_features/audio.nix
      ../../_features/nfs-data.nix
      ../../_features/gaming.nix
      ../../_features/vr.nix
      ../../_features/user-apps.nix
      ../../_features/firefox.nix
      ../../_features/korean.nix
      ../../_features/restic.nix
      ../../_features/desktop-niri.nix
      ../../_features/desktop-noctalia.nix
      ../../_features/greeter-regreet.nix
      ../../_features/elite-dangerous-sync.nix
      ../../_features/remote-access.nix
      inputs.disko.nixosModules.disko
      ../../../hosts/fivenix/disko.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs       = true;
        home-manager.useUserPackages     = true;
        home-manager.backupFileExtension = "backup";
        home-manager.extraSpecialArgs    = { inherit self inputs; };
        home-manager.users.robie.imports = [
          ../../../hosts/fivenix/home.nix
        ];
      }
    ];
  };
}
