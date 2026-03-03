{ lib, config, pkgs, ... }:

{
  options.myHome.nas.enable =
    lib.mkEnableOption "NAS mount/unmount scripts backed by 1Password";

  config = lib.mkIf config.myHome.nas.enable {

    home.packages = [

      # nas-mount [//nas01/fauxbox] [/mnt/fauxbox]
      #
      # Reads credentials from 1Password at runtime — no plaintext secrets
      # on disk. Credentials are written to a tmpfs file for the duration
      # of the mount call, then deleted.
      #
      # Before first use, create a Login item in 1Password:
      #   op item create \
      #     --category login \
      #     --title "NAS" \
      #     --vault "Private" \
      #     username="your-nas-user" \
      #     password="your-nas-password"
      #
      # Then adjust OP_VAULT and OP_ITEM below to match.
      (pkgs.writeShellApplication {
        name = "nas-mount";
        runtimeInputs = [ pkgs._1password-cli pkgs.cifs-utils ];
        text = ''
          # ── Configure these ──────────────────────────────────────────
          DEFAULT_SHARE="//nas01/fauxbox"
          DEFAULT_MOUNT="/mnt/nas/fauxbox"
          OP_VAULT="Private"
          OP_ITEM="NAS"
          # ─────────────────────────────────────────────────────────────

          SHARE="''${1:-$DEFAULT_SHARE}"
          MOUNT="''${2:-$DEFAULT_MOUNT}"

          # Fetch credentials from 1Password.
          # op will prompt for biometric/master-password auth if the vault
          # is not already unlocked by the desktop app.
          NAS_USER=$(op read "op://$OP_VAULT/$OP_ITEM/username")
          NAS_PASS=$(op read "op://$OP_VAULT/$OP_ITEM/password")

          # Write to a tmpfs file — never touches a real disk.
          # The trap guarantees cleanup even if mount fails.
          CREDS=$(mktemp "/run/user/$(id -u)/nas-creds.XXXXXX")
          chmod 600 "$CREDS"
          trap 'rm -f "$CREDS"' EXIT

          printf 'username=%s\npassword=%s\n' "$NAS_USER" "$NAS_PASS" > "$CREDS"

          sudo ${pkgs.cifs-utils}/bin/mount.cifs "$SHARE" "$MOUNT" \
            -o "credentials=$CREDS,uid=$(id -u),gid=$(id -g),file_mode=0644,dir_mode=0755,vers=3.0"

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
  };
}
