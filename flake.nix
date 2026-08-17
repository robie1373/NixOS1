{
  description = "Dry Dock. Robies DRY fleet configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
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
    # Impermanence: tmpfs-root hosts with an explicit persist allowlist
    # (ledger stateless-doctrine.md law 6 / hypervisor-impermanence.md).
    impermanence = {
      url = "github:nix-community/impermanence";
      # The follows is load-bearing, not tidiness. Declared as a bare .url this input
      # pulled its OWN nixpkgs, that copy claimed the lock node literally named
      # "nixpkgs", root's real input was demoted to "nixpkgs_2", and every other
      # input's follows = "nixpkgs" then bound BY NAME to impermanence's stale copy.
      # Found 2026-08-16: ten inputs building against nixpkgs from 2026-01-16 while
      # the systems built against 2026-08-13. Same trap as nix-wrapper-modules on
      # 2026-06-23. Ledger nixos-config.md; verify with: the count of distinct
      # nixpkgs* nodes in flake.lock must be 1.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    import-tree.url = "github:vic/import-tree";

    # nix-wrapper-modules: wraps programs as standalone derivations with embedded config.
    # Used in Phase 1 migration to replace home-manager program modules.
    nix-wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      # Without this follows, nix-wrapper-modules drags in its own
      # nixpkgs-unstable and becomes the lock node *named* `nixpkgs`, which
      # every other input's `follows = "nixpkgs"` then binds to — splitting the
      # fleet across two nixpkgs branches. Follow root's nixos-unstable instead.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LangLab source — pinned here so the server VM always runs a known version.
    # Update with: nix flake update langlab
    langlab = {
      url   = "github:robie1373/langlab";
      flake = false;  # plain source tree, not a flake
    };

    # pages site content — BAKE model (Robie's ruling 2026-07-06): content lives in
    # its own git repo, canonical working copy on flipper (~/proj/pages-content),
    # served from the in-lab git host git.home.lab. nixos-config carries only this
    # pointer, so the payload never reaches GitHub (only the lock's rev/narHash does)
    # — and git.home.lab is in-lab, never GitHub, same boundary as ledger2.
    # 2026-07-21: repinned git+file:// → anonymous read-only git:// on git.home.lab
    # (interim-Forgejo constraint DISSOLVED — any host fetches it with no ssh key and
    # no host-key trust, so vhost2's unattended phase-1 `nix flake update` no longer
    # dies on a flipper-only path OR on git's rotating host key; the mandatory-same-
    # sitting deploy is no longer required). Served by services.gitDaemon on the git
    # guest, exportAll=false + a git-daemon-export-ok marker so ONLY this repo is
    # anonymous (content is already public-on-LAN over HTTP/80). Branch is master.
    # Fetched by name — vhost2 (which runs the unattended phase-1) now resolves
    # home.lab via its default-gateway resolver (fixed 2026-07-21; it was wrongly on
    # 1.1.1.1, which can't resolve lab names — that was this fetch's last blocker).
    # Update with: nix flake update pages-content
    pages-content = {
      url   = "git://git.home.lab/pages-content.git?ref=master";
      flake = false;
    };

    # Noctalia: Qt6/QML desktop shell (bar, notifications, lock screen, wallpaper, launcher).
    # Not in nixpkgs; requires flake input. Cachix available for pre-built binaries.
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # microvm.nix: lightweight type-1 VMs via cloud-hypervisor/QEMU.
    # Used by nixsrv1 (Intel MBP hypervisor role).
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # QMD: local hybrid search engine for markdown (BM25 + vector + LLM reranking).
    # Not in nixpkgs; upstream flake provides packages.default. Tracked here so
    # nix flake update keeps it current automatically.
    qmd = {
      url = "github:tobi/qmd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
