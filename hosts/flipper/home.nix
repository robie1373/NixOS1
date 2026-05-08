{ config, self, inputs, pkgs, ... }: {
  # Set to the Home Manager release you first activated on this host.
  # Do not change this after the first activation.
  home.stateVersion = "25.05";

  myHome.firefox.enable         = true;
  myHome.tablet.enable          = true;
  myHome.mpv.enable             = true;
  # Wrapped program derivations (nix-wrapper-modules — config baked in)
  home.packages = with self.packages.${pkgs.stdenv.hostPlatform.system}; [
    zathura
    foot
    rofi
    waybar
    fish
    okular
    pkgs.nodejs_22  # QMD runtime
  ];
  xdg.mimeApps.defaultApplications."application/pdf" = "org.pwmt.zathura.desktop";
  myHome.imv.enable             = true;
  myHome.mpd.enable             = true;
  myHome.nas.enable             = true;
  myHome.yazi.enable		= true;
  myHome.hyprshot.enable        = true;

  myHome.bearing = {
    enable       = true;
    terminal     = "foot";
    ntfy.server  = "https://ntfy.vimba-stairs.ts.net";
  };

  myHome.teacha = {
    enable      = true;
    package     = inputs.teacha.packages.${pkgs.stdenv.hostPlatform.system}.teacha-daemon;
    pollSeconds = 120;
  };

  services.poweralertd.enable = true;

  # npm global installs (QMD etc.) — writable prefix outside the nix store
  home.sessionPath = [ "${config.home.homeDirectory}/.npm-global/bin" ];

  # QMD — use Qwen3-Embedding for Korean/multilingual support
  home.sessionVariables.QMD_EMBED_MODEL = "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf";
}
