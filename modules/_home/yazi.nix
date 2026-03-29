{ lib, config, ... }:

{
  options.myHome.yazi.enable =
    lib.mkEnableOption "yazi file browser";

  config = lib.mkIf config.myHome.yazi.enable {

    programs.yazi = {
      enable = true;
      shellWrapperName = "y";
    };
  };
}
