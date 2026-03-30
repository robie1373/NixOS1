{ pkgs, ... }:
{
  # cifs-utils provides mount.cifs
  environment.systemPackages = [ pkgs.cifs-utils ];

  # Create the mount point owned by the user
  systemd.tmpfiles.rules = [
    "d /mnt/nas 0755 robie users -"
  ];

  # Allow robie to mount CIFS shares and unmount /mnt/nas without a password
  # prompt. Scope is deliberately narrow:
  #   - mount.cifs: unrestricted target (user controls what they mount)
  #   - umount:     restricted to /mnt/nas subtree
  security.sudo.extraRules = [
    {
      users  = [ "robie" ];
      runAs  = "root";
      commands = [
        {
          command = "${pkgs.cifs-utils}/bin/mount.cifs";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.util-linux}/bin/umount /mnt/nas";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.util-linux}/bin/umount /mnt/nas/*";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # ── Clean unmount on shutdown / reboot / sleep ─────────────────────────
  # Without this, systemd waits up to 90s for the NAS to respond during
  # shutdown. This service lazy-unmounts all CIFS mounts.
  systemd.services.nas-unmount = {
    description = "Unmount NAS CIFS shares on shutdown/sleep";
    wantedBy    = [ "multi-user.target" ];
    conflicts   = [ "shutdown.target" "sleep.target" ];
    before      = [ "shutdown.target" "sleep.target" ];

    serviceConfig = {
      Type              = "oneshot";
      RemainAfterExit   = true;
      ExecStart         = "${pkgs.coreutils}/bin/true";
      ExecStop          = pkgs.writeShellScript "nas-unmount" ''
        ${pkgs.util-linux}/bin/umount -a -f -t cifs 2>/dev/null || true
      '';
    };
  };
}
