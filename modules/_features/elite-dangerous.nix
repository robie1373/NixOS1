{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # ── Native Linux tools ─────────────────────────────────────────────────
    # Both read ED journal files directly; no Wine needed.

    # Tracks Odyssey engineer materials — what you have, what you need, recipes.
    ed-odyssey-materials-helper

    # Uploads market, shipyard, and outfitting data to EDDN / Inara / EDSM etc.
    # On Linux with Steam/Proton, set the journal path in EDMC Preferences →
    # Configuration to:
    #   ~/.local/share/Steam/steamapps/compatdata/359320/pfx/drive_c/users/
    #   steamuser/Saved Games/Frontier Developments/Elite Dangerous
    # (EDMC may auto-detect it; verify on first launch.)
    edmarketconnector

    # ── Windows app manager ────────────────────────────────────────────────
    # Bottles manages Wine prefixes for tools without native Linux builds.
    # Create one bottle for all ED tools; point each at the journal path above.
    #
    # Install into Bottles:
    #   - EDCopilot      — download from edcopilot.com, install the .exe
    #   - Elite Observatory — .NET 6 app; grab the Linux build from GitHub
    #                         (obsrvr.github.io) — may run without Bottles
    #   - EDEngineer     — download from github.com/msarilar/EDEngineer, run .exe
    #   - HCS Voice Packs — install AFTER VoiceAttack (see below)
    #
    # Disabled 2026-05-12: openldap-2.6.13 test017-syncreplication-refresh fails
    # in nixpkgs unstable build sandbox (provider/consumer DB diff). Re-enable
    # once the nixpkgs openldap derivation is fixed upstream.
    # bottles

    # ── Proton prefix tooling ──────────────────────────────────────────────
    # protontricks installs Windows components into Steam Proton prefixes.
    # VoiceAttack requires .NET 8 x64 — install after first VA launch:
    #   protontricks 583010 dotnet80
    protontricks

    # ── VoiceAttack + HCS Voice Packs ─────────────────────────────────────
    # VoiceAttack is on Steam (App ID 583010). Install it from the Steam store;
    # it runs via Proton automatically. HCS Voice Packs install into VoiceAttack's
    # directory inside the Proton prefix:
    #   ~/.local/share/Steam/steamapps/compatdata/583010/pfx/drive_c/users/
    #   steamuser/AppData/Roaming/VoiceAttack/
    # Download HCS packs from hcsvoicepacks.com and follow the installer.

    # ── Tobii ──────────────────────────────────────────────────────────────
    # Tobii gaming drivers (gaze control, foveated rendering) are Windows-only.
    # No nixpkgs package exists. If head tracking only is sufficient, opentrack
    # supports some Tobii cameras — but full gaze integration requires Windows.
  ];
}
