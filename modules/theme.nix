{ ... }:
# Catppuccin Macchiato palette — single source of truth for all colors.
# Every wrapper module imports self.theme rather than hardcoding hex values.
# Reference: https://github.com/catppuccin/catppuccin
{
  flake.theme = {
    name     = "catppuccin-macchiato";
    base     = "#24273a";
    mantle   = "#1e2030";
    crust    = "#181926";
    text     = "#cad3f5";
    subtext1 = "#b8c0e0";
    subtext0 = "#a5adcb";
    overlay2 = "#939ab7";
    overlay1 = "#8087a2";
    overlay0  = "#6e738d";
    surface2 = "#5b6078";
    surface1 = "#494d64";
    surface0 = "#363a4f";
    blue     = "#8aadf4";
    lavender = "#b7bdf8";
    sapphire = "#7dc4e4";
    sky      = "#91d7e3";
    teal     = "#8bd5ca";
    green    = "#a6da95";
    yellow   = "#eed49f";
    peach    = "#f5a97f";
    maroon   = "#ee99a0";
    red      = "#ed8796";
    mauve    = "#c6a0f6";
    pink     = "#f5bde6";
    flamingo = "#f0c6c6";
    rosewater = "#f4dbd6";
  };
}
