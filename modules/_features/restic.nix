# modules/_features/restic.nix
#
# Restic backups to the NAS over SFTP. A host may declare MULTIPLE named backup
# sets — one per thing it backs up:
#
#   mySystem.restic.backups.<name> = {
#     nasPath = "tank/backups/services/<svc>";   # repo location on the NAS (required)
#     paths   = [ "/var/lib/<svc>" ];             # what to back up (required)
#     exclude = [ ... ];                          # optional extra excludes
#     timerOnCalendar = "03:00";                  # optional
#   };
#
# Why named sets and not one-per-host: the backup unit is the *service*, not the
# host. A single-purpose box has one set (named after itself). A HYPERVISOR backs
# up each stateful guest to that guest's own service repo — several sets, all run
# from the one host. Each set is an independent restic repo, timer, and forget
# policy, so guests never share a pile.
#
# Secrets — each set needs two agenix secrets, decryptable by the host that RUNS
# the backup (not necessarily the host the data logically belongs to):
#   secrets/<sshKeySecret>.age        — SSH private key for svc_backup@nas
#   secrets/<repoPasswordSecret>.age  — restic repository encryption password
# These default to restic-backup-<name> / restic-repo-password-<name>. Override
# them when one host runs a backup on behalf of a guest whose credentials were
# minted for a different host: e.g. vhost2 backs up the omada guest into omada's
# existing repo, but with the creds re-encrypted to vhost2's key — so the set is
# named `omada` while its secrets are the vhost2-scoped files.
#
# To add a backup set:
#   1. Generate an SSH keypair for the NAS:  ssh-keygen -t ed25519 -f /tmp/k -N ""
#   2. Store the private key in 1Password (devops/"<sshKeySecret>").
#   3. Add the running host's key as a recipient in secrets/secrets.nix for both
#      <sshKeySecret>.age and <repoPasswordSecret>.age.
#   4. Encrypt: rage -e -R <recipients> -o secrets/<sshKeySecret>.age /tmp/k  (and
#      the repo password into secrets/<repoPasswordSecret>.age).
#   5. Add /tmp/k.pub to svc_backup's authorized_keys on the NAS (TrueNAS UI).
#   6. Declare mySystem.restic.backups.<name> in the host configuration.
# (Reusing an existing repo: skip 1/5, re-encrypt that repo's existing creds to
#  the new running host's key — same NAS key + password, no NAS-side change.)

{ self, config, lib, pkgs, ... }:

let
  cfg = config.mySystem.restic;

  # Common exclude patterns applied to every backup set.
  # Per-set additions go in <set>.exclude.
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

  # NixOS restic backup set for one mySystem.restic.backups.<name>.
  mkBackup = name: b: {
    # sftp: path is absolute on the NAS filesystem. TrueNAS mounts ZFS datasets at /mnt/.
    repository = "sftp:${b.nasUser}@${b.nasHost}:/mnt/${b.nasPath}";

    passwordFile = config.age.secrets.${b.repoPasswordSecret}.path;

    paths   = b.paths;
    exclude = commonExcludes ++ b.exclude;

    # Auto-initialise the repo on first run. Safe — restic init is a no-op if the
    # repo already exists (so reusing an existing repo just works).
    initialize = true;

    timerConfig = {
      OnCalendar         = b.timerOnCalendar;
      RandomizedDelaySec = "1h";   # spread load when multiple sets/hosts share the NAS
      Persistent         = true;   # catch up on missed runs after downtime
    };

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 12"
    ];

    # Use a wrapper script as the SFTP command so the SSH key path is baked in
    # without any spaces in the option value. The NixOS restic module does not
    # quote extraOptions values, so space-separated sftp.args would be shell-split.
    # sftp.command takes a single token (the script store path); it replaces the
    # entire SSH invocation, so the script must establish the full SFTP session.
    extraOptions = [
      "sftp.command=${pkgs.writeShellScript "restic-ssh-${name}" ''
        exec ${pkgs.openssh}/bin/ssh \
          -s \
          -i ${config.age.secrets.${b.sshKeySecret}.path} \
          -o BatchMode=yes \
          -o StrictHostKeyChecking=accept-new \
          ${b.nasUser}@${b.nasHost} \
          sftp
      ''}"
    ];
  };
in
{
  options.mySystem.restic.backups = lib.mkOption {
    default     = {};
    description = ''
      Named restic backup sets to the NAS. Each attribute name is a set name and
      becomes a services.restic.backups.<name> job with its own repo, timer, and
      forget policy. A host may declare any number of sets.
    '';
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
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
          description = "Dataset path on the NAS (without leading /mnt/). The restic repo location.";
          example     = "tank/backups/services/omada";
        };
        paths = lib.mkOption {
          type        = lib.types.listOf lib.types.str;
          description = "Paths to include in this backup set.";
          example     = [ "/var/lib/omada-backups" ];
        };
        exclude = lib.mkOption {
          type        = lib.types.listOf lib.types.str;
          default     = [];
          description = "Extra exclude patterns for this set (common patterns always apply).";
        };
        timerOnCalendar = lib.mkOption {
          type        = lib.types.str;
          default     = "03:00";
          description = "systemd OnCalendar expression for when this set runs.";
        };
        sshKeySecret = lib.mkOption {
          type        = lib.types.str;
          default     = "restic-backup-${name}";
          description = ''
            agenix secret name (without .age) holding the SSH private key for the
            NAS. Must be decryptable by THIS host. Override when reusing another
            service's repo from a different host.
          '';
        };
        repoPasswordSecret = lib.mkOption {
          type        = lib.types.str;
          default     = "restic-repo-password-${name}";
          description = ''
            agenix secret name (without .age) holding the restic repo password.
            Must be decryptable by THIS host.
          '';
        };
      };
    }));
  };

  config = lib.mkIf (cfg.backups != {}) {

    # Decrypt each set's SSH key + repo password at activation. Both are encrypted
    # with this host's SSH host key and live in secrets/. mkMerge tolerates two
    # sets that legitimately share a secret name (identical definitions merge).
    age.secrets = lib.mkMerge (lib.mapAttrsToList (name: b: {
      ${b.sshKeySecret} = {
        file  = "${self}/secrets/${b.sshKeySecret}.age";
        owner = "root";
        mode  = "0400";
      };
      ${b.repoPasswordSecret} = {
        file  = "${self}/secrets/${b.repoPasswordSecret}.age";
        owner = "root";
        mode  = "0400";
      };
    }) cfg.backups);

    services.restic.backups = lib.mapAttrs mkBackup cfg.backups;

    # Wait up to ~90 s for the NAS to be reachable before each backup. Prevents
    # failures when Persistent=true fires the service at boot before inter-VLAN
    # routing to the NAS is up. ExecCondition exit 1 → service skipped (not failed);
    # the timer retries at the next fire.
    systemd.services = lib.mapAttrs' (name: b:
      lib.nameValuePair "restic-backups-${name}" {
        serviceConfig.ExecCondition = pkgs.writeShellScript "restic-nas-reachable-${name}" ''
          for i in $(${pkgs.coreutils}/bin/seq 1 18); do
            if ${pkgs.netcat-openbsd}/bin/nc -z -w 3 ${b.nasHost} 22 2>/dev/null; then
              exit 0
            fi
            sleep 5
          done
          echo "NAS ${b.nasHost} unreachable after 90 s — skipping backup" >&2
          exit 1
        '';
      }) cfg.backups;
  };
}
