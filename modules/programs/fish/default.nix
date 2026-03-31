{ inputs, ... }:
# Fish shell — custom symlinkJoin wrapper (no nix-wrapper-modules support).
# Config is baked in via --init-command "source ${configFish}" on every invocation.
# All aliases from _home/common.nix and _home/desktop-hyprland.nix are included here
# so they survive after programs.fish is removed from the HM config.
{
  perSystem = { pkgs, ... }: {
    packages.fish =
      let
        configFish = pkgs.writeText "config.fish" ''
          set fish_greeting ""   # silence the default welcome banner

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

          # ── Aliases (from _home/desktop-hyprland.nix) ─────────────────────
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

          # Delete all but the last generation
          function cleangen
            echo "running: sudo nix-env --delete-generations +1 --profile /nix/var/nix/profiles/system && nix-env --delete-generations +1 && nix-collect-garbage"
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
