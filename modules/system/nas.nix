{ lib, config, pkgs, ... }:

{
  options.mySystem.nas.enable =
    lib.mkEnableOption "NAS CIFS mount support (mount point + sudoers rules)";

  config = lib.mkIf config.mySystem.nas.enable {

    # cifs-utils provides mount.cifs
    environment.systemPackages = [ pkgs.cifs-utils ];

    # Create the mount point owned by the user
    systemd.tmpfiles.rules = [
      "d /mnt/nas 0755 robie users -"
    ];

    # Allow robie to mount CIFS shares and unmount /mnt/nas without a password
    # prompt. Scope is deliberately narrow:
    #   - mount.cifs: unrestricted target (user controls what they mount)
    #   - umount:     restricted to /mnt/nas only
    security.sudo.extraRules = [
      {
        users = [ "robie" ];
        runAs = "root";
        commands = [
          {
            command = "${pkgs.cifs-utils}/bin/mount.cifs";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${pkgs.util-linux}/bin/umount /mnt/nas";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

  };
}
