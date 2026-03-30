{ inputs, ... }:
# Foot terminal — wrapped with Catppuccin Macchiato theme.
# INI settings map directly to foot.ini sections and keys.
{
  perSystem = { pkgs, ... }: {
    packages.foot = inputs.nix-wrapper-modules.wrappers.foot.wrap {
      inherit pkgs;
      settings = {
        main = {
          font = "JetBrainsMono Nerd Font:size=14";
          pad  = "12x12";
        };

        scrollback = {
          lines = 5000;
        };

        colors-dark = {
          # Catppuccin Macchiato (foot uses hex without #)
          alpha      = "0.8";
          foreground = "cad3f5";
          background = "24273a";
          selection-foreground = "cad3f5";
          selection-background = "363a4f";
          cursor = "24273a f4dbd6";  # text-color cursor-color (rosewater cursor)

          # Black
          regular0 = "494d64"; bright0 = "5b6078";
          # Red
          regular1 = "ed8796"; bright1 = "ed8796";
          # Green
          regular2 = "a6da95"; bright2 = "a6da95";
          # Yellow
          regular3 = "eed49f"; bright3 = "eed49f";
          # Blue
          regular4 = "8aadf4"; bright4 = "8aadf4";
          # Magenta / Mauve
          regular5 = "c6a0f6"; bright5 = "c6a0f6";
          # Cyan / Sky
          regular6 = "91d7e3"; bright6 = "91d7e3";
          # White
          regular7 = "b8c0e0"; bright7 = "a5adcb";
        };
      };
    };
  };
}
