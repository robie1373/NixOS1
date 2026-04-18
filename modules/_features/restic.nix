# modules/_features/restic.nix
#
# Restic backup to NAS via SFTP. One backup set named "nas" per host.
#
# Secrets required (per host, auto-derived from networking.hostName):
#   secrets/restic-backup-<hostname>.age      — SSH private key for svc_backup@nas
#   secrets/restic-repo-password-<hostname>.age — restic repository encryption password
#
# Both secrets are encrypted with the host's SSH host key via age and decrypted
# at activation. The backup service runs as root, unattended, with no OP prompts.
#
# To add a new host:
#   1. Generate keypair: ssh-keygen -t ed25519 -f /tmp/restic-backup-<host> -N ""
#   2. Store private key: op item create --category Login --title restic-backup-<host> ...
#   3. Add host key to secrets/secrets.nix as a recipient
#   4. Encrypt: nix run nixpkgs#age -- --encrypt -r <host-pub-key> \
#                 -o secrets/restic-backup-<host>.age /tmp/restic-backup-<host>
#   5. Generate + store repo password in OP, encrypt same way
#   6. Add the public key from /tmp/restic-backup-<host>.pub to svc_backup's
#      authorized_keys on the NAS (TrueNAS UI → Credentials → Users → svc_backup)
#   7. Enable this module and set mySystem.restic options in host configuration.nix

{ self, config, lib, pkgs, ... }:

let
  cfg      = config.mySystem.restic;
  hostname = config.networking.hostName;

  # Common exclude patterns applied to every backup set.
  # Host-specific additions go in cfg.exclude.
  commonExcludes = [
    "**/.cache"
    "**/.Trash"
    "**/node_modules"
    "**/__pycache__"
    "**/*.pyc"
    "**/*.swp"
    "**/.git/objects"       # git object store — repo is in version control
    "**/lost+found"
  ];
in
{
  options.mySystem.restic = {
    enable = lib.mkEnableOption "restic backups to NAS";

    nasHost = lib.mkOption {
      type        = lib.types.str;
      default     = "192.168.20.12";
      description = "NAS hostname or IP address.";
    };

    nasUser = lib.mkOption {
      type        = lib.types.str;
      default     = "svc_backup";
      description = "SSH user on the NAS.";
    };

    nasPath = lib.mkOption {
      type        = lib.types.str;
      description = "Dataset path on NAS (without leading /mnt/). E.g. tank/backups/laptops/linux/flipper";
      example     = "tank/backups/laptops/linux/flipper";
    };

    paths = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      description = "Paths to include in the backup.";
      example     = [ "/home/robie" ];
    };

    exclude = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = "Additional exclude patterns (common patterns are always applied).";
      example     = [ "/home/robie/tmp-nas" ];
    };

    timerOnCalendar = lib.mkOption {
      type        = lib.types.str;
      default     = "03:00";
      description = "systemd OnCalendar expression for when to run backups.";
    };
  };

  config = lib.mkIf cfg.enable {

    # Decrypt the backup SSH private key and repo password at activation.
    # Both are encrypted with this host's SSH host key and live in secrets/.
    age.secrets."restic-backup-${hostname}" = {
      file  = "${self}/secrets/restic-backup-${hostname}.age";
      owner = "root";
      mode  = "0400";
    };

    age.secrets."restic-repo-password-${hostname}" = {
      file  = "${self}/secrets/restic-repo-password-${hostname}.age";
      owner = "root";
      mode  = "0400";
    };

    services.restic.backups.nas = {
      # sftp: path is absolute on the NAS filesystem. TrueNAS mounts ZFS datasets at /mnt/.
      repository = "sftp:${cfg.nasUser}@${cfg.nasHost}:/mnt/${cfg.nasPath}";

      passwordFile = config.age.secrets."restic-repo-password-${hostname}".path;

      paths   = cfg.paths;
      exclude = commonExcludes ++ cfg.exclude;

      # Auto-initialise the repo on first run. Safe to leave on — restic init is
      # a no-op if the repo already exists.
      initialize = true;

      timerConfig = {
        OnCalendar        = cfg.timerOnCalendar;
        RandomizedDelaySec = "1h";   # spread load when multiple hosts share the NAS
        Persistent        = true;    # catch up on missed runs after downtime
      };

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
      ];

      # Use a wrapper script as the SFTP command so the SSH key path is baked in
      # without any spaces in the option value. The NixOS restic module does not
      # quote extraOptions values in the generated shell script, so space-separated
      # sftp.args would be shell-split and passed incorrectly. sftp.command takes
      # a single token (the script store path) and restic appends the host itself.
      # sftp.command replaces the entire SSH invocation — restic does NOT append
      # the host when this option is set. The script must establish a complete
      # SFTP subsystem session to the NAS on its own.
      extraOptions = [
        "sftp.command=${pkgs.writeShellScript "restic-ssh-${hostname}" ''
          exec ${pkgs.openssh}/bin/ssh \
            -s sftp \
            -i ${config.age.secrets."restic-backup-${hostname}".path} \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=accept-new \
            ${cfg.nasUser}@${cfg.nasHost}
        ''}"
      ];
    };
  };
}
