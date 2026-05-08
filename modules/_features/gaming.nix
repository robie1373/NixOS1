{ pkgs, ... }:
{
  # ── Graphics ──────────────────────────────────────────────────────────
  hardware.graphics.enable       = true;
  hardware.graphics.enable32Bit  = true;  # required for 32-bit Steam games

  # ── Steam ─────────────────────────────────────────────────────────────
  programs.steam = {
    enable                              = true;
    remotePlay.openFirewall             = true;
    localNetworkGameTransfers.openFirewall = true;

    # ProtonGE: community Proton fork with better codec support and
    # compatibility patches that haven't landed in upstream Proton yet.
    extraCompatPackages = [ pkgs.proton-ge-bin ];
  };

  # Steam hardware support: Steam Controller, Steam Deck, Index headset
  hardware.steam-hardware.enable = true;

  # ── GameMode ──────────────────────────────────────────────────────────
  # Temporarily applies CPU governor, scheduler, and I/O tuning when a
  # game requests it (via LD_PRELOAD or the gamemoderun wrapper).
  programs.gamemode.enable = true;

  # ── Gamescope ─────────────────────────────────────────────────────────
  # Micro-compositor for games: FSR upscaling, consistent vsync, no tearing.
  # Use from Steam: Launch options: gamescope -W 1920 -H 1080 -- %command%
  programs.gamescope = {
    enable     = true;
    capSysNice = true;  # lets gamescope set process priority
  };

  environment.systemPackages = with pkgs; [
    mangohud     # in-game performance overlay
gamepad-tool # configure gamepads
    protonup-qt  # GUI for managing Proton/ProtonGE versions
  ];
}
