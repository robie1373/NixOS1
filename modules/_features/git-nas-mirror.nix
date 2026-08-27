# modules/_features/git-nas-mirror.nix
#
# Pull-only git mirrors of the in-lab git server onto the NAS.
#
# WHY (Robie's ruling 2026-08-27, ledger git.md -> "NAS mirror"): canonical git
# lives on the LEAST redundant hardware in the lab and backs up to the MOST.
# The class-4 git-repos.img sits on vhost2's single 238.5 GB disk with no RAID,
# while its restic target `tank` is RAIDZ2 + a mirrored NVMe special vdev. That
# is inverted. The nightly restic image already covers catastrophic loss, but it
# is COLD -- recovery means restoring and loop-mounting an ext4 image. This makes
# recovery `git clone` instead.
#
# Ruled explicitly NOT this job: making the NAS canonical. Two shapes were
# considered and rejected -- TrueNAS serving git (a hand-managed appliance
# service, i.e. a pet, in a lab whose master project is pet elimination), and a
# guest serving with NAS-over-NFS storage (puts a network filesystem in git's
# WRITE path and makes git depend on the NAS being up). Canonical stays local
# and fast on the guest; only the mirror touches the NAS.
#
# SHAPE: a stateless scheduled job. It holds no state of its own -- the mirrors
# live on the NAS, the repo list comes from the server, and the last-success
# stamp is written next to the mirrors. If this host dies, rebuild it and the
# next timer tick resumes; nothing is lost and nothing needs restoring. A copy
# does not inherit the class of its original (stateless-doctrine): these mirrors
# are class 1 here even though the originals are class 4 on the git guest.
#
# READ-ONLY BY CONSTRUCTION: the SSH key this job uses is confined on the server
# to `git-upload-pack` against /var/lib/git/*.git plus a `list-repos` verb. It
# cannot push. A mirror credential that could write to the canonical store would
# be a second writable path into the Ledger, which is exactly what the mirror
# exists to avoid needing.

{ config, lib, pkgs, ... }:

let
  cfg = config.mySystem.gitNasMirror;

  runDir = "/run/git-nas-mirror";

  # Shared ssh invocation. Two options need justifying:
  #
  #   StrictHostKeyChecking=no + UserKnownHostsFile=/dev/null
  #     The git guest's /etc is tmpfs, so it mints a NEW host key on every guest
  #     restart (guest-hostkey-persistence.md, doctrine option A). `accept-new`
  #     is not enough for an unattended job: it accepts an UNKNOWN host, but
  #     still refuses a CHANGED one, so the first guest restart would silently
  #     break mirroring until someone ran ssh-keygen -R. Pinning the key is
  #     impossible for the same reason. This trades MITM detection on a VLAN-20
  #     LAN hop for a job that survives the churn the doctrine deliberately
  #     causes -- and the credential is read-only, so the worst case is fetching
  #     from an impostor, which the ref-verification below then fails on.
  sshBase = "${pkgs.openssh}/bin/ssh -i ${config.age.secrets.${cfg.sshKeySecret}.path} "
    + "-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
    + "-o LogLevel=ERROR -o ConnectTimeout=10";

  ntfySend = pkgs.writeShellScript "git-nas-mirror-notify" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl ]}
    name="$1"; msg="$2"
    # Dedup: at most one push per problem per dedupHours, so an hourly timer
    # failing all night does not become an all-night buzz. /run is tmpfs, so a
    # reboot resets the dedup -- correct, a reboot is worth re-announcing after.
    mkdir -p ${runDir}
    stamp="${runDir}/notified.$name"
    if [ -e "$stamp" ] && [ $(( $(date +%s) - $(stat -c %Y "$stamp") )) -lt ${toString (cfg.dedupHours * 3600)} ]; then
      exit 0
    fi
    topic=$(cat ${config.age.secrets.${cfg.ntfyTopicSecret}.path} 2>/dev/null || true)
    [ -n "$topic" ] || exit 0
    if curl -fsS -m 10 -H "Title: ⚠ git NAS mirror: $name" -H "Priority: high" \
         -H "Tags: floppy_disk,warning" -d "$msg" \
         "${cfg.ntfyUrl}/$topic" >/dev/null 2>&1; then
      touch "$stamp"
    fi
  '';

  mirrorScript = pkgs.writeShellScript "git-nas-mirror" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.git pkgs.openssh pkgs.diffutils pkgs.gawk pkgs.util-linux ]}

    dest="${cfg.mountPoint}"
    src="${cfg.sourcePath}"
    remote="${cfg.sourceUser}@${cfg.sourceHost}"

    export GIT_SSH_COMMAND="${sshBase}"
    # The NAS export maps clients to a fixed uid, so the mirrors on disk may be
    # owned by someone other than the uid running this job. git refuses to touch
    # a repo it does not own ("dubious ownership") and would fail every run.
    # Scoped to this process only -- nothing is written to a global gitconfig.
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0=safe.directory
    export GIT_CONFIG_VALUE_0='*'

    # Refuse to run unless the NAS is actually MOUNTED here. Without this check a
    # down NAS is the worst case, not the obvious one: the mount point still
    # exists as a plain directory, so the job would cheerfully clone every repo
    # onto this host's tmpfs root -- reporting success while mirroring nothing to
    # the NAS, and filling RAM on a hypervisor. Absence of the mount must be loud.
    if ! mountpoint -q "$dest"; then
      ${ntfySend} mount "$dest is NOT mounted -- the NAS export is unavailable. Refusing to run (mirroring to the local disk would look like success)."
      exit 1
    fi
    [ -w "$dest" ] || {
      ${ntfySend} mount "$dest is mounted but NOT writable. Check the NFS export's Maproot setting on the NAS."
      exit 1
    }

    # The repo list comes from the SERVER, not from a copy of it here. The list
    # is declarative in hosts/vhost2/guests/git.nix; duplicating it in this
    # module would mean a repo added there is silently never mirrored, which is
    # precisely the silent failure this whole job exists to avoid.
    repos=$(${sshBase} "$remote" list-repos 2>/dev/null) || {
      ${ntfySend} source "Cannot reach the git server ($remote) to list repos. No mirroring happened this run."
      exit 1
    }
    [ -n "$repos" ] || {
      ${ntfySend} source "The git server returned an EMPTY repo list. Refusing to proceed (an empty list would look like success while mirroring nothing)."
      exit 1
    }

    failed=""
    count=0
    for repo in $repos; do
      d="$dest/$repo.git"
      url="ssh://$remote$src/$repo.git"

      if [ -d "$d" ]; then
        git --git-dir="$d" remote update --prune >/dev/null 2>&1 || {
          failed="$failed $repo(fetch)"; continue
        }
      else
        git clone --quiet --mirror "$url" "$d" >/dev/null 2>&1 || {
          failed="$failed $repo(clone)"; rm -rf "$d"; continue
        }
      fi

      # Track the source's HEAD symref. `git remote update` syncs refs but NEVER
      # moves HEAD, so a mirror made before a default-branch rename keeps
      # pointing at the old name. A bare repo whose HEAD names a ref that does
      # not exist stops advertising HEAD entirely, and `git clone` from it lands
      # the caller in an EMPTY working tree -- a rehydration failure that only
      # shows up the day you need to rehydrate. (This exact trap was found on
      # four lab repos on 2026-08-27; see ledger git.md.)
      head_ref=$(git ls-remote --symref "$url" HEAD 2>/dev/null | awk '/^ref:/ {print $2; exit}')
      if [ -n "$head_ref" ]; then
        git --git-dir="$d" symbolic-ref HEAD "$head_ref" 2>/dev/null || true
      fi

      # Verify the ARTIFACT, not the exit code. "git fetch returned 0" says the
      # transport worked; it does not say the mirror now matches. Compare the
      # full advertised ref set, HEAD symref included, on both sides.
      if ! diff -q \
           <(git ls-remote --symref "$url" 2>/dev/null | sort) \
           <(git ls-remote --symref "$d"   2>/dev/null | sort) >/dev/null 2>&1; then
        failed="$failed $repo(refs-differ)"
        continue
      fi

      count=$((count + 1))
    done

    if [ -n "$failed" ]; then
      ${ntfySend} repos "Mirrored $count repo(s); FAILED:$failed"
      exit 1
    fi

    # Stamp lives WITH the mirrors on the NAS, not in local state: it survives a
    # rebuild of this host, and the staleness check then reads the artifact
    # rather than this job's own self-report.
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$dest/.last-success" 2>/dev/null || true
    rm -f ${runDir}/notified.* 2>/dev/null || true
    echo "git-nas-mirror: OK -- $count repo(s) verified ref-identical"
  '';

  stalenessScript = pkgs.writeShellScript "git-nas-mirror-staleness" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    stamp="${cfg.mountPoint}/.last-success"
    max=$(( ${toString cfg.maxAgeHours} * 3600 ))

    # Covers the failure the per-run alert cannot see: the timer never firing at
    # all (unit masked, host down for days, mount silently gone). Success is
    # silent by design -- a mirror that is working should never buzz the phone.
    if [ ! -e "$stamp" ]; then
      ${ntfySend} staleness "No successful mirror run has ever been recorded at $stamp."
      exit 1
    fi
    age=$(( $(date +%s) - $(stat -c %Y "$stamp") ))
    if [ "$age" -ge "$max" ]; then
      ${ntfySend} staleness "Last successful mirror was $(( age / 3600 ))h ago (limit ${toString cfg.maxAgeHours}h). The mirror on the NAS is going stale."
      exit 1
    fi
  '';
in
{
  options.mySystem.gitNasMirror = {
    enable = lib.mkEnableOption "pull-only git mirrors of the in-lab git server onto the NAS";

    nasHost = lib.mkOption {
      type = lib.types.str;
      default = "192.168.20.12";
      description = "NAS address serving the mirror export.";
    };
    nasExport = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/tank/backups/git-mirror";
      description = ''
        NFS export path on the NAS holding the bare mirrors. Deliberately its own
        dataset with an export restricted to this host, NOT the general
        /mnt/tank/data share: that one is exported to VLAN 10 and VLAN 20 with
        mapall, so plaintext ledger2 and work mirrors there would be readable by
        any NFS-capable device on the trusted VLAN. Robie's call, 2026-08-27.
      '';
    };
    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/git-mirror";
      description = "Local mount point for the NAS mirror export.";
    };

    sourceHost = lib.mkOption {
      type = lib.types.str;
      default = "git.home.lab";
      description = "The canonical in-lab git server.";
    };
    sourceUser = lib.mkOption {
      type = lib.types.str;
      default = "git";
      description = "SSH user on the git server.";
    };
    sourcePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/git";
      description = "Absolute path to the bare repos on the git server.";
    };
    sshKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "git-mirror-key";
      description = ''
        agenix secret (without .age) holding the private key for the mirror's
        read-only account on the git server. Must be decryptable by THIS host.
      '';
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = ''
        How often to mirror. Hourly, not daily: the nightly restic image already
        provides a ~24h-cold copy, so a daily mirror would add durability
        without adding freshness. An incremental fetch of these repos over the
        LAN costs seconds.
      '';
    };
    maxAgeHours = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Alert if the newest successful mirror run is at least this many hours old.";
    };
    dedupHours = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Minimum interval between repeat ntfy pushes for the same problem.";
    };
    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://ntfy.home.lab";
      description = "ntfy base URL (LAN path -- alerting must not depend on Tailscale).";
    };
    ntfyTopicSecret = lib.mkOption {
      type = lib.types.str;
      default = "ntfy-alert-topic";
      description = "agenix secret (without .age) holding the ntfy topic name.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.supportedFilesystems = [ "nfs" ];

    systemd.tmpfiles.rules = [ "d ${cfg.mountPoint} 0755 root root -" ];

    # Automount, not a boot mount: the NAS being down must never delay or block
    # this hypervisor's boot. `hard` is deliberate -- these are WRITES, and a
    # soft mount returning EIO mid-fetch can leave a torn packfile in the mirror.
    # mount-timeout bounds the hang, and the service's own timeout bounds the
    # rest, so nothing can wedge indefinitely.
    fileSystems.${cfg.mountPoint} = {
      device = "${cfg.nasHost}:${cfg.nasExport}";
      fsType = "nfs";
      options = [
        "x-systemd.automount"
        "noauto"
        "x-systemd.idle-timeout=300"
        "x-systemd.mount-timeout=30"
        "nfsvers=4.1"
        "hard"
        "noatime"
      ];
    };

    # A transient automount miss parks the .mount unit in `failed`, and
    # switch-to-configuration exits non-zero if ANY unit is failed -- which makes
    # a NAS blip look like a broken deploy. Same fix as flipper's nfs-data.nix.
    systemd.units."${lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" cfg.mountPoint)}.mount" = {
      overrideStrategy = "asDropin";
      text = ''
        [Unit]
        OnFailure=git-nas-mirror-mount-reset.service
      '';
    };
    systemd.services.git-nas-mirror-mount-reset = {
      description = "Clear the transient failed state of the git mirror NFS mount";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.systemd.package}/bin/systemctl reset-failed ${lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" cfg.mountPoint)}.mount";
      };
    };

    age.secrets.${cfg.sshKeySecret} = {
      file = ../../secrets/${cfg.sshKeySecret}.age;
      owner = "root";
      mode = "0400";
    };
    # Same declaration as alerting.nix / patch-automation.nix (identical values
    # merge cleanly) — this module runs on hosts that may import neither.
    age.secrets.${cfg.ntfyTopicSecret} = {
      file = ../../secrets/${cfg.ntfyTopicSecret}.age;
      mode = "0444";
    };

    systemd.services.git-nas-mirror = {
      description = "Mirror the in-lab git repos to the NAS (pull-only)";
      unitConfig.RequiresMountsFor = cfg.mountPoint;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${mirrorScript}";
        TimeoutStartSec = "30min";
        # Skip (not fail) when the NAS is simply unreachable -- the staleness
        # check owns the "gone too long" alarm, so a brief NAS outage does not
        # need to raise anything.
        ExecCondition = pkgs.writeShellScript "git-nas-mirror-nas-reachable" ''
          exec ${pkgs.netcat-openbsd}/bin/nc -z -w 5 ${cfg.nasHost} 2049
        '';
      };
    };
    systemd.timers.git-nas-mirror = {
      description = "Periodic git -> NAS mirror";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };

    systemd.services.git-nas-mirror-staleness = {
      description = "Alert if the git NAS mirror has gone stale";
      unitConfig.RequiresMountsFor = cfg.mountPoint;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${stalenessScript}";
      };
    };
    systemd.timers.git-nas-mirror-staleness = {
      description = "Periodic git NAS mirror staleness check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "20min";
        OnUnitActiveSec = "2h";
        Persistent = true;
      };
    };
  };
}
