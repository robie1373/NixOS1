{ lib, config, pkgs, ... }:
{
  options.mySystem.vmGuest.enable = lib.mkEnableOption "VM guests";

  config = lib.mkIf config.mySystem.vmGuest.enable {
  
    services.qemuGuest.enable = true;
    services.spice-vdagentd.enable = true;
    environment.systemPackages = with pkgs; [ spice-vdagent ];

    };
}
