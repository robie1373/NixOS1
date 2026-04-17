{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "fivenix";

  # ── NVIDIA GPU ───────────────────────────────────────────────────────────────
  # RTX 4070 (AD104, Ada Lovelace). Proprietary driver required for CUDA.
  # open = false: use proprietary blobs (open kernel modules are not production-
  # ready for CUDA workloads as of 25.11 — re-evaluate when they stabilise).
  # modesetting.enable: required for DRM KMS; enables proper Wayland + GBM support.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open              = false;
    modesetting.enable = true;
    nvidiaSettings     = true;   # include nvidia-settings GUI
    package            = config.boot.kernelPackages.nvidiaPackages.stable;

    # Desktop — no suspend/resume needed. Disable power management to prevent
    # the GPU dropping to a low-power state between inferences, which adds
    # cold-start latency. Ollama's KEEP_ALIVE=-1 keeps models warm anyway.
    powerManagement.enable = false;
  };

  # hardware.graphics.* and hardware.graphics.enable32Bit are set by
  # _features/gaming.nix (also imported for this host). No need to repeat.

  # ── Ollama (local LLM — primary purpose of this host) ───────────────────────
  # Exposed on 0.0.0.0 so other Tailscale hosts (flipper, nixos1) can send
  # inference requests without installing Ollama locally.
  #
  # RTX 4070 has 12 GB VRAM. With a second GPU (3070, 8 GB), Ollama auto-
  # distributes layers across both cards — see the dual-GPU note in docs/.
  services.ollama = {
    enable       = true;
    acceleration = "cuda";
    host         = "0.0.0.0";
    port         = 11434;

    # Performance tuning:
    # KEEP_ALIVE=-1   — never evict a model from VRAM; always warm on first request.
    # NUM_PARALLEL=4  — 20 GB combined VRAM (4070 12 GB + 2060 Super 8 GB).
    # FLASH_ATTENTION — uses flash-attention kernel; faster and lower memory bandwidth.
    #                   Supported on Ampere / Ada Lovelace. Disable if you see errors.
    environmentVariables = {
      OLLAMA_KEEP_ALIVE    = "-1";
      OLLAMA_NUM_PARALLEL  = "4";
      OLLAMA_FLASH_ATTENTION = "1";
    };
  };

  # ── CUDA binary cache ────────────────────────────────────────────────────────
  # Avoids building torchWithCuda and other CUDA packages from source.
  # Without this, torchWithCuda is a multi-hour compile. Verify the key at:
  # https://cuda-maintainers.cachix.org
  nix.settings = {
    substituters = [
      "https://cuda-maintainers.cachix.org"
    ];
    trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  # ── System packages ──────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
      # whisper-cpp: C++ reimplementation with GGML backend.
      # Faster startup, lower overhead than Python Whisper, and CUDA support
      # via GGML (no PyTorch/triton involved — avoids nixpkgs CUDA Python mess).
      # Python openai-whisper + CUDA is broken in nixpkgs 25.11 due to duplicate
      # triton derivations in the closure; use whisper-cpp instead.
      whisper-cpp

      # CUDA developer toolchain (nvcc, profiler, libraries)
      cudaPackages.cudatoolkit

      # GPU process monitor — shows VRAM usage, SM utilisation, power draw.
      # nvtopPackages.full covers NVIDIA + AMD + Intel in one binary.
      nvtopPackages.full

      # General utilities
      btop
      wget
      tree
      ripgrep

      # Gaming tools are added by _features/gaming.nix
    ];

  # ── KDE Plasma 6 ─────────────────────────────────────────────────────────────
  # Full desktop for gaming, browser, general use. No Hyprland on this host.
  services.xserver.enable         = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable          = true;
    wayland.enable  = true;
  };

  # ── Dual-GPU KWin fix ────────────────────────────────────────────────────────
  # With two NVIDIA GPUs, KWin Wayland gets confused about which DRM device to
  # use for the display, causing a freeze at login. Pin it to the 4070 (card0).
  # The 2060 Super (card1) is still available to CUDA/Ollama — this only affects
  # the display compositor. Verify card paths with: ls -la /dev/dri/
  environment.sessionVariables.KWIN_DRM_DEVICES = "/dev/dri/card0";

  # ── Unfree allowlist ─────────────────────────────────────────────────────────
  # mkForce overrides common.nix's predicate with a superset that adds NVIDIA,
  # CUDA, and Steam entries. 1password entries are re-included here.
  nixpkgs.config.allowUnfreePredicate = lib.mkForce (pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      # From common.nix (kept here since mkForce replaces, not extends)
      "1password"
      "1password-gui"
      # NVIDIA driver
      "nvidia-x11"
      "nvidia-settings"
      "nvidia-persistenced"
      # CUDA toolkit components
      "cudatoolkit"
      "cuda-merged"
      "cuda_cudart"
      "cuda_nvcc"
      "cuda_nvtx"
      "libcufft"
      "libcusolver"
      "libcublas"
      "libnpp"
      # Steam (added by _features/gaming.nix)
      "steam"
      "steam-original"
      "steam-run"
      "steam-unwrapped"
    ]
  );

  # ── Networking ───────────────────────────────────────────────────────────────
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin        = "no";
  services.openssh.settings.PasswordAuthentication = true;

  # Allow Ollama API from Tailscale peers. Add other LAN CIDRs here if needed.
  networking.firewall.allowedTCPPorts = [ 11434 ];

  # ── Virpil HOTAS ─────────────────────────────────────────────────────────────
  # Vendor ID 0x3344 covers the full Virpil range (Alpha, Constellation, etc.).
  # GROUP=input matches the group robie is already in via common.nix extraGroups.
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTRS{idVendor}=="3344", GROUP="input", MODE="0664"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3344", GROUP="input", MODE="0664"
  '';

  # ── User extras ──────────────────────────────────────────────────────────────
  # render group: direct access to /dev/dri/renderD128 (CUDA, ROCm, VA-API)
  # without sudo. Common group for GPU compute without full video group access.
  users.users.robie.extraGroups = [ "render" ];

  system.stateVersion = "25.11";
}
