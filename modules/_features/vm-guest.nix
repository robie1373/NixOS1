{ pkgs, ... }:
{
  services.qemuGuest.enable      = true;
  services.spice-vdagentd.enable = true;
  environment.systemPackages     = with pkgs; [ spice-vdagent ];
}
