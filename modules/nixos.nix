{ ... }:
# Host definitions live in modules/hosts/<name>/default.nix — auto-discovered
# by import-tree. This file only declares the perSystem architectures.
{
  systems = [ "aarch64-linux" "x86_64-linux" ];
}
