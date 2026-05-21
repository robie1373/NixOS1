{ pkgs, ... }:
{
  # cifs-utils provides mount.cifs
  environment.systemPackages = [
    pkgs.cifs-utils.bin

    # nas-mount [//nas01/fauxbox] [/mnt/fauxbox]
    # Reads credentials from 1Password at runtime — no plaintext secrets on disk.
    (pkgs.writeShellApplication {
      name = "nas-mount";
      runtimeInputs = [ ];
      text = ''
        DEFAULT_SHARE="//nas01/fauxbox"
        OP_VAULT="devops"
        OP_ITEM="NAS"

        SHARE="''${1:-$DEFAULT_SHARE}"
        SHARE_NAME="$(basename "$SHARE")"
        MOUNT="''${2:-/mnt/nas/$SHARE_NAME}"

        sudo mkdir -p "$MOUNT"

        NAS_USER=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields username)
        NAS_PASS=$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields password --reveal)

        CREDS=$(mktemp "/run/user/$(id -u)/nas-creds.XXXXXX")
        chmod 600 "$CREDS"
        trap 'rm -f "$CREDS"' EXIT

        printf 'username=%s\npassword=%s\ndomain=%s\n' "$NAS_USER" "$NAS_PASS" "WORKGROUP" > "$CREDS"

        sudo ${pkgs.cifs-utils.bin}/bin/mount.cifs "$SHARE" "$MOUNT" \
          -o "credentials=$CREDS,uid=$(id -u),gid=$(id -g),file_mode=0644,dir_mode=0755,vers=3.0,sec=ntlmssp"

        echo "Mounted $SHARE at $MOUNT"
      '';
    })

    # nas-umount [/mount/point]
    (pkgs.writeShellApplication {
      name = "nas-umount";
      runtimeInputs = [ ];
      text = ''
        MOUNT="''${1:-/mnt/nas}"
        sudo ${pkgs.util-linux}/bin/umount "$MOUNT"
        echo "Unmounted $MOUNT"
      '';
    })
  ];

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
          command = "${pkgs.cifs-utils.bin}/bin/mount.cifs";
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
