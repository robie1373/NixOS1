{ inputs, ... }:
# Zathura PDF viewer — wrapped with Catppuccin Macchiato theme.
# Phase 1 spike: validates that nix-wrapper-modules integrates with this flake.
# Settings sourced from the legacy modules/_home/zathura.nix.
#
# Plugin note: default wrapper plugins are [zathura_cb zathura_djvu zathura_ps] — no PDF.
# We override plugins to add zathura_pdf_poppler.
#
# Color note: girara (zathura's UI lib) does not support 8-digit RGBA hex (#rrggbbaa).
# highlight-color and highlight-active-color are omitted; zathura uses its built-in defaults.
#
# smooth-scroll is not a valid zathura option in current nixpkgs; omitted.
{
  perSystem = { pkgs, ... }: {
    packages.zathura = inputs.nix-wrapper-modules.wrappers.zathura.wrap {
      inherit pkgs;
      plugins = with pkgs.zathuraPkgs; [
        zathura_pdf_poppler
        zathura_cb
        zathura_djvu
        zathura_ps
      ];
      settings = {
        # ── Catppuccin Macchiato ────────────────────────────────────────────
        "default-bg"            = "#24273a";
        "default-fg"            = "#cad3f5";

        "statusbar-fg"          = "#cad3f5";
        "statusbar-bg"          = "#363a4f";

        "inputbar-bg"           = "#1e2030";
        "inputbar-fg"           = "#cad3f5";

        "notification-bg"         = "#363a4f";
        "notification-fg"         = "#cad3f5";
        "notification-error-bg"   = "#363a4f";
        "notification-error-fg"   = "#ed8796";
        "notification-warning-bg" = "#363a4f";
        "notification-warning-fg" = "#eed49f";

        "completion-bg"           = "#363a4f";
        "completion-fg"           = "#8aadf4";
        "completion-highlight-fg" = "#24273a";
        "completion-highlight-bg" = "#8aadf4";

        # Recolor mode: inverts PDF to dark-bg/light-text. Toggle with <Ctrl+r>.
        "recolor-lightcolor" = "#24273a";
        "recolor-darkcolor"  = "#cad3f5";
        "recolor"            = true;
        "recolor-keephue"    = false;

        # ── Behaviour ──────────────────────────────────────────────────────
        "selection-clipboard"  = "clipboard";
        "scroll-step"          = 50;
        "zoom-step"            = 10;
        "statusbar-home-tilde" = true;

        "font" = "JetBrainsMono Nerd Font 11";
      };
    };
  };
}
