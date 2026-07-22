# fivenix — OFFLINE since 2026-07-05 (Robie): powered down until further notice.
#
# Its nixosConfiguration is disabled below so fleet-wide evals/builds don't spend
# time on a desktop that isn't running (it's a heavy build — niri/noctalia/gaming/
# VR). The host config in hosts/fivenix/, its disko, and its secrets recipients are
# left intact. To bring fivenix back: set `online = true`.
{ inputs, self, ... }:

let
  online = false;
in
inputs.nixpkgs.lib.optionalAttrs online {
  flake.nixosConfigurations.fivenix = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules = [
      ../../../hosts/fivenix/configuration.nix
      ../../_features/common.nix
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
    ];
  };
}
