{ inputs, ... }:
let
  # mkHost: desktop/workstation hosts — includes home-manager, Hyprland, etc.
  # Rewrite note: this is the desktop-side helper. Modify freely during the rewrite.
  mkHost = { system, modules }: inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs; };
    inherit system modules;
  };

  # mkServer: headless lab servers — no home-manager, no desktop, no audio.
  # Used for all NixOS VMs provisioned in Proxmox (ntfy, Kanidm, Blocky, etc.).
  # Rewrite note: this is the lab-infrastructure helper. Keep separate from mkHost
  # so the desktop rewrite cannot accidentally affect server configs.
  mkServer = { system, modules }: inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs; };
    inherit system modules;
  };
in
{
  systems = [ "aarch64-linux" "x86_64-linux" ];

  flake.nixosConfigurations = {

    # ── Lab servers (mkServer — no home-manager, no desktop) ─────────────────

    ntfy = mkServer {
      system = "x86_64-linux";
      modules = [
        ../hosts/ntfy/configuration.nix
      ];
    };

    # ── Desktop / workstation hosts (mkHost — includes home-manager) ─────────

    flipper = mkHost {
      system = "x86_64-linux";
      modules = [
        ../hosts/flipper/configuration.nix
        ./_system/common.nix
        ./_system/1password.nix
        ./_system/audio.nix
        #./_system/desktop-kde.nix
        ./_system/desktop-hyprland.nix
        ./_system/nas.nix
        ./_system/speaker-fix.nix
        inputs.disko.nixosModules.disko
        ../hosts/flipper/disko.nix
        ./_system/gaming.nix
        inputs.home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.robie.imports = [
            inputs.nix-index-database.hmModules.nix-index
            ../hosts/flipper/home.nix
            ./_home/common.nix
            ./_home/1password.nix
            ./_home/gemini-cli.nix
            ./_home/claude.nix
            ./_home/obsidian.nix
            ./_home/bearing.nix
            ./_home/desktop-hyprland.nix
            ./_home/firefox.nix
            ./_home/tablet.nix
            ./_home/mpv.nix
            ./_home/zathura.nix
            ./_home/imv.nix
            ./_home/mpd.nix
            ./_home/nas.nix
            ./_home/yazi.nix
            ./_home/hyprshot.nix
            ./_home/anki-bin.nix
          ];
        }
      ];
    };

    nixos1 = mkHost {
      system = "aarch64-linux";
      modules = [
        ../hosts/nixos1/configuration.nix
        ./_system/common.nix
        ./_system/1password.nix
        ./_system/audio.nix
        #./_system/desktop-kde.nix
        ./_system/desktop-hyprland.nix
        ./_system/vm-guest.nix
        inputs.home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.robie.imports = [
            inputs.nix-index-database.hmModules.nix-index
            ../hosts/nixos1/home.nix
            ./_home/common.nix
            ./_home/1password.nix
            ./_home/gemini-cli.nix
            ./_home/claude.nix
            ./_home/obsidian.nix
            ./_home/bearing.nix
            ./_home/desktop-hyprland.nix
            ./_home/firefox.nix
            ./_home/yazi.nix
            ./_home/hyprshot.nix
          ];
        }
      ];
    };


#    nixos2 = mkHost {
#      system = "x86_64-linux";
#      modules = [
#        ../hosts/nixos1/configuration.nix
#        ./_system/common.nix
#        ./_system/1password.nix
#        ./_system/audio.nix
#        ./_system/desktop-kde.nix
#        inputs.home-manager.nixosModules.home-manager {
#          home-manager.useGlobalPkgs = true;
#          home-manager.useUserPackages = true;
#          home-manager.users.robie.imports = [
#            ../hosts/nixos2/home.nix
#            ./_home/common.nix
#            ./_home/1password.nix
#          ];
#	}
#      ];
#    };
#
#    major-ant = mkHost {
#      system = "x86_64-linux";
#      modules = [
#        ../hosts/major-ant/configuration.nix
#        ./_system/common.nix
#        ./_system/1password.nix
#        ./_system/audio.nix
#        ./_system/desktop-kde.nix
#        ./_system/vm-guest.nix
#        inputs.home-manager.nixosModules.home-manager {
#          home-manager.useGlobalPkgs = true;
#          home-manager.useUserPackages = true;
#          home-manager.users.robie.imports = [
#            ../hosts/major-ant/home.nix
#            ./_home/common.nix
#            ./_home/1password.nix
#          ];
#	}
#      ];
#    };

  };
}
