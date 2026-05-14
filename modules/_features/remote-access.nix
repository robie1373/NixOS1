{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    rustdesk
    waypipe
  ];

  # RustDesk client daemon — handles incoming remote desktop connections.
  # Runs as a user service so it has access to the graphical session.
  systemd.user.services.rustdesk = {
    description = "RustDesk remote desktop daemon";
    wantedBy    = [ "graphical-session.target" ];
    after       = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.rustdesk}/bin/rustdesk --service";
      Restart   = "on-failure";
    };
  };
}
