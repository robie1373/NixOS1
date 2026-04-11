{ ... }:
# Okular document viewer (KDE/Qt).
# No config injection needed — Okular manages its own settings via ~/.config/okularrc.
{
  perSystem = { pkgs, ... }: {
    packages.okular = pkgs.okular;
  };
}
