{ inputs, self, ... }:
{
  flake.nixosConfigurations.flipper = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      # Overlay: adds pkgs.qmd from the upstream qmd flake (tracked as a flake input,
      # so nix flake update keeps it current automatically).
      #
      # The upstream flake's wrapper hard-sets LD_LIBRARY_PATH to sqlite only and
      # omits libstdc++. node-llama-cpp's prebuilt CPU binary links against
      # libstdc++.so.6, and qmd runs under bun (which, unlike node, does not carry
      # libstdc++ in its own process image), so embedding/search die with a
      # misleading NoBinaryFoundError. Append gcc's cc.lib to the wrapper so the
      # prebuilt CPU backend loads. See ~/ledger2/qmd.md for the full diagnosis.
      { nixpkgs.overlays = [ (final: _: {
        qmd = inputs.qmd.packages.x86_64-linux.default.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            sed -i "s|^\(export LD_LIBRARY_PATH='[^']*\)'|\1:${final.stdenv.cc.cc.lib}/lib'|" $out/bin/qmd
          '';
        });
      }) ]; }
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
      ../../_features/user-apps.nix
      ../../_features/bearing.nix
      ../../_features/firefox.nix
      ../../_features/mpd.nix
      ../../_features/restic.nix
      ../../_features/restic-staleness-alert.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs         = true;
        home-manager.useUserPackages       = true;
        home-manager.backupFileExtension   = "backup";
        home-manager.extraSpecialArgs      = { inherit self inputs; };
        home-manager.users.robie.imports   = [
          ../../../hosts/flipper/home.nix
        ];
      }
    ];
  };
}
