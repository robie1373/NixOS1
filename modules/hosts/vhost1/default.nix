# modules/hosts/vhost1/default.nix
#
# vhost1 flake output declaration (all-nixos-lab rung 5).
# Formerly pve (Proxmox) — converted in place to NixOS + microvm.nix.
# See ledger proxmox-to-microvm.md Phase B3.
#
# Mirrors vhost2/nixsrv1: the microvm.nix HOST module must be imported here (it
# provides the microvm.host options that hypervisor.nix turns on). Individual guest
# microVM definitions live in hosts/vhost1/configuration.nix, added one at a time
# at conversion (Phase B3 bring-up).

{ inputs, self, ... }:
{
  flake.nixosConfigurations.vhost1 = inputs.nixpkgs.lib.nixosSystem {
    system      = "x86_64-linux";
    specialArgs = { inherit inputs self; };
    modules     = [
      inputs.microvm.nixosModules.host
      ../../../hosts/vhost1/configuration.nix
    ];
  };
}
