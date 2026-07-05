# modules/hosts/vhost2/default.nix
#
# vhost2 flake output declaration (all-nixos-lab rung 4).
# Formerly pve2 (Proxmox) — converted in place to NixOS + microvm.nix.
# See ledger proxmox-to-microvm.md Phase B2.
#
# Mirrors nixsrv1: the microvm.nix HOST module must be imported here (it provides
# the microvm.host options that hypervisor.nix turns on). Individual guest
# microVM definitions live in hosts/vhost2/configuration.nix, added one at a time
# at conversion (Phase B2 step 5).

{ inputs, self, ... }:
{
  flake.nixosConfigurations.vhost2 = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [
      inputs.microvm.nixosModules.host
      ../../../hosts/vhost2/configuration.nix
    ];
  };
}
