# Stub — will be replaced with real hardware config during first deployment.
#
# When deploying with nixos-anywhere, pass the generate flag:
#
#   nixos-anywhere \
#     --flake .#flipper \
#     --generate-hardware-config nixos-generate-config ./hosts/flipper/hardware-configuration.nix \
#     root@<flipper-ip>
#
# nixos-anywhere will overwrite this file with the real hardware config,
# then proceed with the install.

{ ... }: { }
