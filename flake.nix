{
  description = "Dry Dock. Robies DRY fleet configuration";

  # Binary caches for inputs that aren't in the nixpkgs cache.
  # nixConfig applies immediately during `nix flake update`; the NixOS option
  # in desktop-noctalia.nix makes it persistent after rebuild.
  nixConfig = {
    extra-substituters      = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    # nixpkgs-stable: used by hosts that prioritise reliability over freshness.
    # Currently: fivenix (gaming desktop — CUDA/PyTorch stack is fragile on unstable).
    # Intentionally does NOT follow the unstable nixpkgs input.
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    hyprland.url = "github:hyprwm/Hyprland";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url= "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # agenix: age-encrypted secrets management for NixOS hosts.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixos-generators: builds NixOS images (proxmox, iso, qcow2, etc.)
    # Rewrite note: deprecated as of NixOS 25.05 — migrate to native nixpkgs image API.
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # import-tree: auto-discovers all .nix files under ./modules as flake-parts modules.
    # Directories prefixed with _ are excluded (used to quarantine legacy NixOS modules
    # during migration — see modules/_system/ and modules/_home/).
    import-tree.url = "github:vic/import-tree";

    # nix-wrapper-modules: wraps programs as standalone derivations with embedded config.
    # Used in Phase 1 migration to replace home-manager program modules.
    nix-wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";

    # LangLab source — pinned here so the server VM always runs a known version.
    # Update with: nix flake update langlab
    langlab = {
      url   = "github:robie1373/langlab";
      flake = false;  # plain source tree, not a flake
    };

    # Teacha: ambient spaced repetition daemon.
    # Update with: nix flake update teacha
    teacha = {
      url = "github:robie1373/teacha";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia: Qt6/QML desktop shell (bar, notifications, lock screen, wallpaper, launcher).
    # Not in nixpkgs; requires flake input. Cachix available for pre-built binaries.
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
