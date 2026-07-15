# Steam & Gaming Setup

## Hardware Context

**flipper** has an Intel Core Ultra 7 256V with Arc Graphics 140V (Xe2/Lunar Lake).
This is a capable integrated GPU with full Vulkan support via Mesa's `iris` driver.
It runs many indie games, 2D titles, older 3D games, and emulated titles well.
Demanding AAA titles from the last few years are unlikely to be playable at full settings.

---

## What Gets Installed

| Component           | What it does                                                  |
|---------------------|---------------------------------------------------------------|
| `programs.steam`    | Steam client + Proton (Windows game compatibility layer)      |
| ProtonGE            | Community Proton fork — better codec and game support         |
| GameMode            | CPU/scheduler tuning while a game is running                  |
| MangoHud            | In-game overlay: FPS, frametimes, GPU/CPU usage, temps        |
| Gamescope           | Micro-compositor for better windowing and FSR upscaling       |
| Lutris              | Non-Steam games (GOG, Epic, itch.io, emulators)               |
| Heroic              | Native Epic and GOG launcher                                  |
| `hardware.graphics` | 32-bit Vulkan + OpenGL for 32-bit Steam games                 |

---

## NixOS Configuration

### System module (`modules/system/gaming.nix`)

Create `modules/system/gaming.nix` and add it to flipper's imports in `parts/nixos.nix`.
Enable it with `mySystem.gaming.enable = true` in `hosts/flipper/configuration.nix`.

```nix
{ lib, config, pkgs, ... }:

{
  options.mySystem.gaming.enable =
    lib.mkEnableOption "Steam and gaming stack";

  config = lib.mkIf config.mySystem.gaming.enable {

    # ── Graphics ──────────────────────────────────────────────────────────
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;   # required for 32-bit Steam games

    # ── Steam ─────────────────────────────────────────────────────────────
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
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
    # Games that support it request GameMode automatically; others need:
    #   Launch options: gamemoderun %command%
    programs.gamemode.enable = true;

    # ── Gamescope ─────────────────────────────────────────────────────────
    # Micro-compositor for games. Enables:
    #   - FSR (FidelityFX Super Resolution) upscaling
    #   - Consistent vsync behaviour
    #   - Nested compositor mode (no tearing)
    # Use from Steam: Launch options: gamescope -W 1920 -H 1080 -- %command%
    programs.gamescope = {
      enable = true;
      capSysNice = true;   # lets gamescope set process priority
    };

    environment.systemPackages = with pkgs; [
      # In-game performance overlay — enable per-game in Steam launch options:
      #   MANGOHUD=1 %command%
      # Or globally: mangohud %command%
      mangohud

      # Non-Steam game launchers
      lutris
      heroic

      # Useful utilities
      gamepad-tool      # configure gamepads
      protonup-qt       # GUI for managing Proton/ProtonGE versions
    ];
  };
}
```

---

## Using Steam

### First Launch
1. Open Steam from the launcher or run `steam`
2. Log in
3. In Steam → Settings → Compatibility:
   - Enable **"Enable Steam Play for all other titles"**
   - Select **"Proton Experimental"** or **"GE-Proton"** (GE-Proton generally has better compatibility)

### Per-Game Launch Options

Right-click game → Properties → Launch Options.

| Goal                          | Launch option                                    |
|-------------------------------|--------------------------------------------------|
| Force Proton (any game)       | Set in Compatibility tab, not launch options     |
| Enable MangoHud overlay       | `MANGOHUD=1 %command%`                           |
| Use GameMode                  | `gamemoderun %command%`                          |
| Use Gamescope                 | `gamescope -W 1920 -H 1080 -f -- %command%`      |
| All of the above              | `gamemoderun mangohud gamescope -f -- %command%` |
| Force specific Vulkan device  | `VK_ICD_FILES=/run/opengl-driver/share/vulkan/icd.d/intel_icd.x86_64.json %command%` |

### ProtonGE
ProtonGE (`GE-Proton`) is available in Steam as a compatibility tool after
enabling it in `extraCompatPackages`. Select it per-game in:
Properties → Compatibility → Force the use of a specific Steam Play compatibility tool → GE-Proton

---

## Intel Arc Specifics

The Arc 140V uses Intel's ANV (Anvil) Vulkan driver via Mesa. A few notes:

- **DXVK** (DirectX 9/10/11 → Vulkan translation) works well on Arc. Prefer it over WINED3D.
- **VKD3D-Proton** (DirectX 12 → Vulkan) works but may be slower than AMD/NVIDIA for DX12 games.
- **OpenGL games** use Mesa's `iris` driver and generally work well.
- **32-bit games** require `hardware.graphics.enable32Bit = true` — already set.
- **Ray tracing** is not supported on the 140V hardware.
- **FSR/upscaling** via Gamescope is useful since the 140V has limited fillrate.

### Arc Driver Environment Variables

```bash
# If a game uses the wrong GPU (e.g., on a dual-GPU system):
export INTEL_GPU_MIN_FREQ_MHZ=300
export INTEL_GPU_MAX_FREQ_MHZ=2000
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1

# Force Vulkan over OpenGL for better performance in some games:
export DXVK_GPLASYNC=1    # async pipeline compilation (reduces stutters)
```

Set these per-game in Steam launch options if needed:
```
DXVK_GPLASYNC=1 %command%
```

---

## Non-Steam Games

### Heroic (Epic / GOG)
Run `heroic`. Log in to Epic or GOG. Games use Wine/Proton under the hood —
configure in Heroic → Settings → Wine to use the system Proton or ProtonGE.

### Lutris
Run `lutris`. Provides access to community install scripts for many games
and platforms (Battle.net, EA App, itch.io, etc.).

---

## Emulation

The Arc 140V is well-suited for emulation. Common emulators in nixpkgs:

| System         | Emulator        | Package          |
|----------------|-----------------|------------------|
| PS2            | PCSX2           | `pcsx2`          |
| PS3            | RPCS3           | `rpcs3`          |
| Switch         | Ryujinx         | `ryujinx`        |
| Wii/GC         | Dolphin         | `dolphin-emu`    |
| Various (RetroArch) | RetroArch  | `retroarch`      |

Add to `environment.systemPackages` in the gaming module as needed.

---

## Controller Support

Steam handles most controllers natively (Xbox, PlayStation, Switch Pro, Steam Controller).
`hardware.steam-hardware.enable = true` installs udev rules for all of them.

For non-Steam games:
```bash
# Check if controller is recognised
ls /dev/input/js*

# Test inputs
sudo jstest /dev/input/js0
```

---

## Checking Compatibility

Before buying a game, check:
- **ProtonDB** (https://www.protondb.com) — community reports for Linux/Proton compatibility
- **Are We Anti-Cheat Yet?** (https://areweanticheatyet.com) — anti-cheat status (many EAC/BattlEye games work on Linux now)

---

## Troubleshooting

```bash
# Check Vulkan is working
nix shell nixpkgs#vulkan-tools -c vulkaninfo | grep deviceName

# Check 32-bit Vulkan
nix shell nixpkgs#vulkan-tools -c vulkaninfo --summary

# Steam not launching — check logs
~/.steam/steam/logs/

# Game crashing — check Proton logs
PROTON_LOG=1 %command%    # (in Steam launch options)
# Logs go to: ~/.steam/steam/logs/

# MangoHud not showing — check it's installed
which mangohud
MANGOHUD=1 mangohud glxgears   # quick test

# GameMode not working
systemctl status gamemoded
gamemoded -t                   # run tests
```

---

## What Not to Expect

- **Demanding AAA titles** (Cyberpunk 2077, Alan Wake 2, etc.) — the 140V lacks
  the raw GPU power. Expect low settings and possibly below 30fps.
- **Anti-cheat in multiplayer** — some games (Valorant, PUBG) use kernel-level
  anti-cheat that doesn't work on Linux.
- **DLSS** — NVIDIA exclusive. FSR (AMD open standard) works via Gamescope and
  is available in many games.
