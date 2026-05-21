{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/_features/elite-dangerous.nix
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
  # Exposed on 0.0.0.0 so other Tailscale hosts can send
  # inference requests without installing Ollama locally.
  #
  # RTX 4070 has 12 GB VRAM. With a second GPU (3070, 8 GB), Ollama auto-
  # distributes layers across both cards — see the dual-GPU note in docs/.
  services.ollama = {
    enable  = true;
    package = pkgs.ollama-cuda;
    host    = "0.0.0.0";
    port    = 11434;

    environmentVariables = {
      OLLAMA_KEEP_ALIVE      = "-1";  # never evict from VRAM
      OLLAMA_NUM_PARALLEL    = "2";   # 12 GB VRAM (RTX 4070 only, 2060 Super removed 2026-05-15)
      OLLAMA_FLASH_ATTENTION = "1";   # Ada Lovelace supports this; disable if errors appear
      OLLAMA_NUM_CTX         = "65536";
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

      # Migrated from _home/ in Phase 3.7 (_home/obsidian.nix and anki-bin.nix deleted)
      obsidian
      anki-bin

      # Migrated from _home/ in Phase 3.7 HM removal
      gemini-cli
      claude-code
      yazi
      git-secrets
      uv
      imv
      (mpv.override {
        scripts = with mpvScripts; [ uosc sponsorblock ];
        mpv-unwrapped = mpv-unwrapped.override { waylandSupport = true; };
      })
    ];

  # ── Firefox ──────────────────────────────────────────────────────────────────
  programs.firefox = {
    enable = true;
    policies = {
      DisableTelemetry         = true;
      EnableTrackingProtection = { Value = true; Locked = false; };
      Homepage                 = { URL = "about:blank"; Locked = false; };
      NewTabPage               = false;
    };
  };

  # ── imv image viewer ─────────────────────────────────────────────────────────
  xdg.mime.defaultApplications = {
    "image/jpeg"    = "imv.desktop";
    "image/png"     = "imv.desktop";
    "image/gif"     = "imv.desktop";
    "image/webp"    = "imv.desktop";
    "image/tiff"    = "imv.desktop";
    "image/bmp"     = "imv.desktop";
    "image/svg+xml" = "imv.desktop";
    "application/pdf" = "org.pwmt.zathura.desktop";
  };

  systemd.user.tmpfiles.rules = [
    "L+ %h/.config/imv/config - - - - ${pkgs.writeText "imv-config" ''
      [options]
      background        = 24273a
      overlay_font      = JetBrainsMono Nerd Font:13
      overlay_text_color       = cad3f5ff
      overlay_background_color = 1e2030cc
      slideshow_duration = 0

      [aliases]
      q = quit
    ''}"
  ];

  # ── KDE Plasma 6 ─────────────────────────────────────────────────────────────
  # Full desktop for gaming, browser, general use. No Hyprland on this host.
  services.xserver.enable         = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable          = true;
    wayland.enable  = true;
  };

  # KWIN_DRM_DEVICES: pin KWin to the RTX 4070 (card1 = 0x2786).
  # Must use environment.variables (not sessionVariables) so SDDM picks it up
  # before the compositor starts.
  environment.variables.KWIN_DRM_DEVICES = "/dev/dri/card1";

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

  # ── Open WebUI ───────────────────────────────────────────────────────────────
  # Web frontend for Ollama. Accessible from home VLAN (192.168.7.x) on :8080.
  # WEBUI_AUTH=false: no login required — home network only, not publicly exposed.
  services.open-webui = {
    enable       = true;
    host         = "0.0.0.0";
    port         = 8080;
    openFirewall = true;
    environment  = {
      OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_AUTH      = "false";
    };
  };

  # ── Restic backups ───────────────────────────────────────────────────────────
  mySystem.restic = {
    enable  = true;
    nasPath = "tank/backups/laptops/linux/fivenix";
    paths   = [ "/home/robie" ];
    exclude = [
      "/home/robie/nas"       # NFS automount — NAS data, not a local backup target
      # Ollama model weights — re-pullable, can be 10s of GB
      "/home/robie/.ollama"
      # Whisper / HuggingFace model caches
      "/home/robie/.cache/whisper"
      "/home/robie/.cache/huggingface"
      # Steam game files — saves/config in userdata/ are kept, just not the games
      "/home/robie/.local/share/Steam/steamapps"
    ];
  };

  system.stateVersion = "25.11";
}
