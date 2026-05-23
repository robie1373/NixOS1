{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # rustdesk  # suspended — needs config/testing before enabling
    # waypipe   # suspended — XDG_RUNTIME_DIR env var removed 2026-05-22; SetEnv+PAM untested
  ];

  # RustDesk client daemon — suspended along with the package above.
  # systemd.user.services.rustdesk = {
  #   description = "RustDesk remote desktop daemon";
  #   wantedBy    = [ "graphical-session.target" ];
  #   after       = [ "graphical-session.target" ];
  #   serviceConfig = {
  #     ExecStart = "${pkgs.rustdesk}/bin/rustdesk --service";
  #     Restart   = "on-failure";
  #   };
  # };
}
