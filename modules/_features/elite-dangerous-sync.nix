{ pkgs, ... }:
let
  # ── Path constants ──────────────────────────────────────────────────────────
  # NAS base (NFS automount via nfs-data.nix)
  nasBase = "$HOME/nas";

  # NAS backup root — dated snapshots land under versions/YYYYMMDD/
  nasBackup = "${nasBase}/elite-backup";

  # Proton prefix root (Steam app ID 359320 — Elite Dangerous)
  edProton = "$HOME/.local/share/Steam/steamapps/compatdata/359320/pfx/drive_c/users/steamuser";

  # Config paths within prefix
  edBindings = "${edProton}/Saved Games/Frontier Developments/Elite Dangerous/Options/Bindings";

  # Native Linux app configs (XDG paths — not in Proton prefix)
  edmcConfig = "$HOME/.config/EDMarketConnector";

  # ── ed-setup: NAS → local ───────────────────────────────────────────────────
  # Run once after Steam has initialized the ED Proton prefix (launch ED at
  # least once before running this). Idempotent — safe to re-run.
  edSetup = pkgs.writeShellScriptBin "ed-setup" ''
    set -euo pipefail

    echo "==> ed-setup: copying configs from NAS to local"

    check_prefix() {
      local path="$1" name="$2"
      if [[ ! -d "$path" ]]; then
        echo "  ✗ $name Proton prefix not found: $path"
        echo "    Launch $name via Steam at least once first."
        return 1
      fi
    }

    # Elite Dangerous bindings
    check_prefix "${edProton}" "Elite Dangerous" || exit 1
    mkdir -p "${edBindings}"
    ${pkgs.rsync}/bin/rsync -av --delete \
      "${nasBase}/eliteDangerous/Bindings/" \
      "${edBindings}/"
    echo "  ✓ ED bindings"

    # EDMC (native Linux — XDG config)
    mkdir -p "${edmcConfig}"
    ${pkgs.rsync}/bin/rsync -av --delete \
      "${nasBase}/eliteDangerous/EDMC/" \
      "${edmcConfig}/"
    echo "  ✓ EDMC config"

    echo "==> Done. Run 'ed-backup' to verify round-trip."
  '';

  # ── ed-backup: local → NAS (versioned) ─────────────────────────────────────
  # Called by the systemd path watcher on config change, or run manually.
  # Changed files are snapshotted to versions/YYYYMMDD/ for rollback.
  edBackup = pkgs.writeShellScriptBin "ed-backup" ''
    set -euo pipefail

    VERSION_DIR="${nasBackup}/versions/$(date +%Y%m%d-%H%M%S)"

    sync_path() {
      local src="$1" dst="$2" label="$3"
      if [[ ! -e "$src" ]]; then
        echo "  ~ $label: source not found, skipping"
        return 0
      fi
      mkdir -p "$dst" "$VERSION_DIR"
      ${pkgs.rsync}/bin/rsync -av \
        --backup --backup-dir="$VERSION_DIR/$(basename "$dst")" \
        "$src/" "$dst/"
      echo "  ✓ $label"
    }

    echo "==> ed-backup: syncing configs to NAS"

    sync_path "${edBindings}"  "${nasBase}/eliteDangerous/Bindings"  "ED bindings"
    sync_path "${edmcConfig}"  "${nasBase}/eliteDangerous/EDMC"      "EDMC"

    # Prune version snapshots older than 90 days
    find "${nasBackup}/versions" -maxdepth 1 -type d -mtime +90 -exec rm -rf {} + 2>/dev/null || true

    echo "==> Done. Snapshot: $VERSION_DIR"
  '';

  # ── Watcher service ─────────────────────────────────────────────────────────
  backupService = {
    description = "Elite Dangerous config backup to NAS";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = "${edBackup}/bin/ed-backup";
    };
  };

in {
  environment.systemPackages = [ edSetup edBackup pkgs.rsync ];

  systemd.user.services.ed-backup = backupService;

  # Path units added here after interactive file selection.
  # Pattern:
  #   systemd.user.paths.ed-backup-<name> = {
  #     description = "Watch <file> for ED backup";
  #     pathConfig = {
  #       PathModified  = "<absolute-path-to-file>";
  #       Unit          = "ed-backup.service";
  #     };
  #     wantedBy = [ "default.target" ];
  #   };
}
