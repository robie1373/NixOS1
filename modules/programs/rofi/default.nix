{ inputs, ... }:
# Rofi launcher — wrapped with Catppuccin Macchiato theme.
# The theme is a pkgs.writeText .rasi file referenced via @theme in config.rasi.
# settings maps to the `configuration { }` section in the generated config.rasi.
{
  perSystem = { pkgs, ... }: {
    packages.rofi =
      let
        theme = pkgs.writeText "catppuccin-macchiato.rasi" ''
          * {
            bg-col:          #24273a;
            bg-col-light:    #363a4f;
            border-col:      #24273a;
            selected-col:    #363a4f;
            blue:            #8aadf4;
            fg-col:          #cad3f5;
            fg-col2:         #ed8796;
            grey:            #6e738d;

            width:           600;
            font:            "JetBrainsMono Nerd Font 14";
          }

          element-text, element-icon, mode-switcher {
            background-color: inherit;
            text-color:       inherit;
          }

          window {
            height:           360px;
            border:           3px;
            border-color:     @border-col;
            background-color: @bg-col;
            border-radius:    12px;
          }

          mainbox {
            background-color: @bg-col;
          }

          inputbar {
            children:         [ prompt, entry ];
            background-color: @bg-col;
            border-radius:    5px;
            padding:          2px;
          }

          prompt {
            background-color: @blue;
            padding:          6px;
            text-color:       @bg-col;
            border-radius:    3px;
            margin:           20px 0 0 20px;
          }

          textbox-prompt-colon {
            expand:           false;
            str:              ":";
          }

          entry {
            padding:          6px;
            margin:           20px 0 0 10px;
            text-color:       @fg-col;
            background-color: @bg-col;
          }

          listview {
            border:           0 2px 0;
            padding:          6px 0 6px;
            margin:           10px 0 0 20px;
            columns:          2;
            lines:            5;
            background-color: @bg-col;
          }

          element {
            padding:          5px;
            background-color: @bg-col;
            text-color:       @fg-col;
          }

          element-icon {
            size:             25px;
          }

          element selected {
            background-color: @selected-col;
            text-color:       @fg-col2;
          }

          mode-switcher {
            spacing:          0;
          }

          button {
            padding:          10px;
            background-color: @bg-col-light;
            text-color:       @grey;
            vertical-align:   0.5;
            horizontal-align: 0.5;
          }

          button selected {
            background-color: @bg-col;
            text-color:       @fg-col;
          }

          message {
            background-color: @bg-col-light;
            margin:           2px;
            padding:          2px;
            border-radius:    5px;
          }

          textbox {
            padding:          6px;
            margin:           20px 0 0 20px;
            text-color:       @fg-col;
            background-color: @bg-col-light;
          }
        '';
      in
      inputs.nix-wrapper-modules.wrappers.rofi.wrap {
        inherit pkgs;
        # "${theme}" coerces the derivation to its store-path string so the
        # rofi module's `builtins.isAttrs` check treats it as a path, not a
        # Rasi section attrset.
        theme    = "${theme}";
        settings = {
          modi               = "drun,run,window";
          show-icons         = true;
          icon-theme         = "Papirus-Dark";
          drun-display-format = "{name}";
          disable-history    = false;
        };
      };
  };
}
