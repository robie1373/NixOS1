{ inputs, ... }:
# Fish shell — custom symlinkJoin wrapper (no nix-wrapper-modules support).
# Config is baked in via --init-command "source ${configFish}" on every invocation.
# Aliases originally lived in HM modules (common, desktop-hyprland) and are
# preserved here so they survive once programs.fish is removed from the HM config.
{
  perSystem = { pkgs, ... }: {
    packages.fish =
      let
        configFish = pkgs.writeText "config.fish" ''
          set fish_greeting ""   # silence the default welcome banner

          # ── User PATH additions ───────────────────────────────────────────
          fish_add_path ~/.npm-global/bin

          # ── QMD — use Qwen3 multilingual embeddings ───────────────────────
          set -x QMD_EMBED_MODEL "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"

          # ── Aliases (from _home/common.nix home.shellAliases) ─────────────
          alias ll 'ls -lh'
          alias la 'ls -ah'
          alias rebuild 'nh os switch /home/robie/nixos-config'
          alias build   'nh os build  /home/robie/nixos-config'
          alias ntest   'nh os test   /home/robie/nixos-config'
          alias gs      'git status'

          # gc needs $argv[1] explicitly — use a function instead of alias
          function gc
            sudo nix-env --delete-generations $argv[1] --profile /nix/var/nix/profiles/system \
              && nix-env --delete-generations $argv[1] \
              && sudo nix-collect-garbage
          end

          # ── Aliases (carried over from the old HM desktop module) ─────────
          alias mount-phone 'mkdir -p ~/mnt/iphone && ${pkgs.ifuse}/bin/ifuse ~/mnt/iphone'

          # ── Functions ─────────────────────────────────────────────────────

          # Change the wallpaper: wallpaper /path/to/image.png
          function wallpaper
            pkill swaybg
            ${pkgs.swaybg}/bin/swaybg -i $argv[1] -m fill &
          end

          # Check battery level via acpi
          function battery
            nix-shell -p acpi --run "acpi -b"
          end

          # Delete all but the last system + user generation, then collect garbage.
          # Destructive and irreversible: if the most recent generation is broken,
          # there is no fallback. Requires typing "yes" to confirm.
          function cleangen
            if contains -- --help $argv; or contains -- -h $argv
              echo "cleangen — delete all system and user generations except the most recent, then run nix-collect-garbage."
              echo
              echo "Usage: cleangen"
              echo
              echo "Takes no arguments. Destructive: only the most recent generation survives."
              return 0
            end

            if test (count $argv) -gt 0
              echo "cleangen: unexpected argument(s): $argv" >&2
              echo "Run 'cleangen --help' for usage." >&2
              return 2
            end

            echo "About to delete ALL system and user generations except the most recent,"
            echo "then run nix-collect-garbage. If the most recent generation is broken you"
            echo "will have no fallback. Commands:"
            echo "  sudo nix-env --delete-generations +1 --profile /nix/var/nix/profiles/system"
            echo "  nix-env --delete-generations +1"
            echo "  nix-collect-garbage"
            echo
            read -P "Type 'yes' to continue, anything else aborts: " -l confirm
            if test "$confirm" != yes
              echo "Aborted."
              return 1
            end

            sudo nix-env --delete-generations +1 --profile /nix/var/nix/profiles/system \
              && nix-env --delete-generations +1 \
              && nix-collect-garbage
          end
        '';

        fishWrapper = pkgs.writeShellScriptBin "fish" ''
          exec ${pkgs.fish}/bin/fish --init-command "source ${configFish}" "$@"
        '';
      in
      # NixOS environment.shells and users.users.*.shell require packages to have
      # a shellPath attribute.  Use passthru (not //) so the result stays a
      # real derivation — the // operator produces a plain attrset that breaks
      # Nix string interpolation in the NixOS shell/passwd activation scripts.
      pkgs.symlinkJoin {
        name = "fish";
        # fishWrapper listed first — its bin/fish shadows pkgs.fish's bin/fish.
        # pkgs.fish still provides completions, functions, man pages, and $__fish_data_dir.
        paths = [ fishWrapper pkgs.fish ];
        passthru.shellPath = "/bin/fish";
        meta.mainProgram  = "fish";
      };
  };
}
