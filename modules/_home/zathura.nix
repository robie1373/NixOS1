{ lib, config, ... }:

{
  options.myHome.zathura.enable =
    lib.mkEnableOption "zathura PDF reader";

  config = lib.mkIf config.myHome.zathura.enable {

    programs.zathura = {
      enable = true;

      options = {
        # ── Catppuccin Macchiato ────────────────────────────────────────
        default-bg            = "#24273a";
        default-fg            = "#cad3f5";

        statusbar-fg          = "#cad3f5";
        statusbar-bg          = "#363a4f";

        inputbar-bg           = "#1e2030";
        inputbar-fg           = "#cad3f5";

        notification-bg         = "#363a4f";
        notification-fg         = "#cad3f5";
        notification-error-bg   = "#363a4f";
        notification-error-fg   = "#ed8796";
        notification-warning-bg = "#363a4f";
        notification-warning-fg = "#eed49f";

        highlight-color        = "#eed49f40"; # search highlight
        highlight-active-color = "#8aadf440"; # active search result

        completion-bg           = "#363a4f";
        completion-fg           = "#8aadf4";
        completion-highlight-fg = "#24273a";
        completion-highlight-bg = "#8aadf4";

        # Recolor mode inverts the PDF to dark-bg/light-text for comfortable reading.
        # Toggle at runtime with <Ctrl+r>.
        recolor-lightcolor = "#24273a";
        recolor-darkcolor  = "#cad3f5";
        recolor            = true;
        recolor-keephue    = false;

        # ── Behaviour ────────────────────────────────────────────────────
        selection-clipboard  = "clipboard"; # yank selected text to system clipboard
        smooth-scroll        = true;
        scroll-step          = 50;
        zoom-step            = 10;
        statusbar-home-tilde = true;        # show ~ instead of /home/user

        font = "JetBrainsMono Nerd Font 11";
      };
    };

    # Register zathura as the default handler for PDF files
    xdg.mimeApps.defaultApplications = {
      "application/pdf" = "org.pwmt.zathura.desktop";
    };
  };
}
