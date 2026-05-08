{ inputs, ... }:
# Re-exports the noctalia-shell package into perSystem.packages so it's
# referenceable as selfpkgs.noctalia alongside other wrapper-module programs.
{
  perSystem = { pkgs, ... }: {
    packages.noctalia =
      inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
