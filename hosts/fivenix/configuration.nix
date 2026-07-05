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
  # ready for CUDA workloads — re-evaluate when open modules stabilise for CUDA).
  # modesetting.enable: required for DRM KMS; enables proper Wayland + GBM support.
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
  # Exposed on 0.0.0.0 so other Tailscale hosts (flipper, etc.) can send
  # inference requests without installing Ollama locally.
  # RTX 4070 — 12 GB VRAM (sole GPU as of 2026-05-13).
  services.ollama = {
    enable  = true;
    package = pkgs.ollama-cuda;
    host    = "0.0.0.0";
    port    = 11434;

    # Performance tuning:
    # KEEP_ALIVE=-1   — never evict a model from VRAM; always warm on first request.
    # NUM_PARALLEL=4  — 12 GB VRAM (RTX 4070).
    # FLASH_ATTENTION — uses flash-attention kernel; faster and lower memory bandwidth.
    #                   Supported on Ada Lovelace. Disable if you see errors.
    environmentVariables = {
      OLLAMA_KEEP_ALIVE    = "-1";
      OLLAMA_NUM_PARALLEL  = "4";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_NUM_CTX = "65536";
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

  # ── ydotool (uinput key injection for gaming macros) ─────────────────────────
  # Used to send key sequences to Elite Dangerous from scripts (e.g. request docking).
  # ydotoold runs as a system service; robie must be in the ydotool group.
  # Scripts call `ydotool key <key>` and ED receives them via uinput regardless of
  # Wayland/XWayland — as long as ED has compositor focus.
  programs.ydotool.enable = true;

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

      # ed-request-docking: sends the "Request Docking Permission" key sequence to
      # Elite Dangerous via ydotool. Triggered by Mod+G niri keybind (ED must have
      # focus — niri handles the hotkey at compositor level without stealing focus).
      #
      # Key mappings from RobieCustomBinds2026.4.2.binds:
      #   Key_1       = FocusLeftPanel
      #   Key_Insert  = CyclePreviousPage  (tab left — smash left to reach Navigation)
      #   Key_Home    = CycleNextPage      (tab right)
      #   DownArrow   = UI_Down
      #   Ctrl+Alt+I  = UI_Select
      #
      # Contacts tab is 2 presses right from Navigation (Nav → Transactions → Contacts).
      # MENU_OFFSET: down-arrow presses in context menu before confirming.
      # Tune if "Request Docking" isn't the first context menu option.
      (pkgs.writeShellScriptBin "ed-request-docking" ''
        # NixOS programs.ydotool puts the socket at /run/ydotoold/socket, but
        # ydotool falls back to $XDG_RUNTIME_DIR/.ydotool_socket when the env
        # var is absent — wrong path. Set it explicitly so niri spawn-sh works.
        export YDOTOOL_SOCKET=/run/ydotoold/socket

        PREV_TAB="insert"
        NEXT_TAB="home"
        UI_DOWN="down"
        UI_SELECT="leftctrl+leftalt+i"
        MENU_OFFSET=0   # down-arrow presses in context menu before confirming;
                        # tune if "Request Docking" isn't the first item

        # Open / focus left panel (assumed to be on Navigation tab)
        ydotool key 1
        sleep 0.4

        # Navigate right to Contacts (Navigation → Transactions → Contacts)
        ydotool key "$NEXT_TAB"
        sleep 0.25
        ydotool key "$NEXT_TAB"
        sleep 0.35

        # Select first contact (targeted station should be at top)
        ydotool key "$UI_DOWN"
        sleep 0.25
        ydotool key "$UI_SELECT"
        sleep 0.5

        # Navigate to "Request Docking Permission" in context menu
        for _i in $(seq 1 "$MENU_OFFSET"); do
          ydotool key "$UI_DOWN"
          sleep 0.12
        done

        # Confirm
        ydotool key "$UI_SELECT"
        sleep 0.4

        # Return to Navigation tab (Contacts → Transactions → Navigation)
        ydotool key "$PREV_TAB"
        sleep 0.15
        ydotool key "$PREV_TAB"
      '')

      # Gaming tools are added by _features/gaming.nix
    ];

  # ── Desktop ──────────────────────────────────────────────────────────────────
  # Niri + noctalia + regreet — configured via _features/desktop-niri.nix,
  # _features/desktop-noctalia.nix, and _features/greeter-regreet.nix imported
  # in modules/hosts/fivenix/default.nix.
  #
  # NVIDIA driver loading: services.xserver.videoDrivers triggers the
  # hardware/nvidia.nix module in NixOS regardless of whether X11 is enabled.
  # Wayland DRM/KMS is handled by hardware.nvidia.modesetting.enable = true above.
  services.xserver.videoDrivers = [ "nvidia" ];

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
  services.openssh.settings.StreamLocalBindUnlink     = true;
  services.openssh.settings.AllowStreamLocalForwarding = "yes";
  services.openssh.settings.SetEnv                    = "XDG_RUNTIME_DIR=/run/user/1000";

  security.pam.services.sshd.startSession = true;

  # 11434 — Ollama API
  # 4500  — EDCopter web UI (access from flipper or any LAN browser)
  networking.firewall.allowedTCPPorts = [ 11434 4500 ];

  # ── Bluetooth ────────────────────────────────────────────────────────────────
  # No blueman — noctalia provides the bluetooth widget. Matches the flipper
  # cleanup from 2026-05-23: blueman-applet was a hyprland-era carryover that
  # fights noctalia for control of the radio.
  hardware.bluetooth.enable        = true;
  hardware.bluetooth.powerOnBoot   = true;

  # xpadneo: Xbox One/Series BT driver. The in-kernel hid-xbox is unreliable
  # over Bluetooth; xpadneo handles rumble, analog triggers, and reconnection.
  boot.extraModulePackages = [ config.boot.kernelPackages.xpadneo ];

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
  users.users.robie.extraGroups = [ "render" "ydotool" ];

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
  mySystem.restic.backups.fivenix = {
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
