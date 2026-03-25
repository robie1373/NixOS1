{
  description = "Dry Dock. Robies DRY fleet configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
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

    # nixos-generators: builds NixOS images in various formats (proxmox, iso, qcow2, etc.)
    # Used here to produce the golden bootstrap image imported into Proxmox as a template.
    # New lab VMs are cloned from that template; nixos-anywhere then installs the real config.
    # Rewrite note: this is a lab-infrastructure concern, not a desktop concern.
    # Keep in any flake that manages server provisioning; safe to omit from a desktop-only flake.
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { flake-parts, ... }: 
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "aarch64-linux" "x86_64-linux" ];
      imports = [
        ./parts/nixos.nix      # nixosConfigurations: all hosts (desktop + lab servers)
        ./parts/packages.nix   # packages: lab tooling outputs (bootstrap image, etc.)
                               # Rewrite note: packages.nix is lab-infrastructure only.
                               # Desktop rewrite can ignore or exclude it safely.
      ];
    };
}
