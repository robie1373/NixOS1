# Runbook: Add a New Host

---

## Decide: desktop host or lab server?

- **Desktop/workstation** (has a user, home-manager, Hyprland) → use `mkHost` in `parts/nixos.nix`
- **Headless lab server** (no user, no desktop, no audio) → use `mkServer`

---

## Steps

**1. Install NixOS on the machine and generate hardware config**

```bash
# On the target machine:
sudo nixos-generate-config --show-hardware-config > /tmp/hardware-configuration.nix
```

Note the `system.stateVersion` value — you'll need it in step 3.

**2. Copy hardware-configuration.nix into the repo**

```bash
cp /tmp/hardware-configuration.nix hosts/<name>/hardware-configuration.nix
```

> **Gotcha:** Never edit `hardware-configuration.nix` by hand. It is auto-generated and reflects the actual hardware. Changes will be overwritten the next time `nixos-generate-config` runs.

**3. Create `hosts/<name>/configuration.nix`**

Copy from a similar existing host and adjust:

```nix
{ config, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "<name>";

  # Enable features for this host
  mySystem.audio.enable = true;
  # mySystem.desktopHyprland.enable = true;
  # etc.

  environment.systemPackages = with pkgs; [
    # host-specific packages
  ];

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.PasswordAuthentication = true;

  # !! Use the stateVersion from nixos-generate-config output. NEVER change this. !!
  system.stateVersion = "25.11";
}
```

> **Gotcha — stateVersion:** Use the version emitted by `nixos-generate-config` on the target machine. Do not copy it from another host. Do not change it after first boot — it controls stateful migration behaviour.

**4. Create `hosts/<name>/home.nix`** (desktop hosts only)

```nix
{ ... }: {
  # !! Use the Home Manager version active when you first activate on this host. !!
  home.stateVersion = "25.05";

  myHome.desktopHyprland.enable = true;
  # Add other myHome feature flags here
}
```

> **Gotcha — home.stateVersion:** Set this to the HM release when you first activate. Check the current nixpkgs input to determine the right value. Do not copy blindly from another host.

> **Gotcha — terminal:** VMs (QEMU/KVM) must use `foot` — kitty requires real OpenGL and fails on virtual GPUs. Physical hosts use `kitty`.

**5. Add the host to `parts/nixos.nix`**

**Desktop host:**

```nix
<name> = mkHost {
  system = "x86_64-linux";   # or "aarch64-linux"
  modules = [
    ../hosts/<name>/configuration.nix
    ../modules/system/common.nix
    ../modules/system/1password.nix
    ../modules/system/audio.nix
    ../modules/system/desktop-hyprland.nix
    # ../modules/system/vm-guest.nix   # add for QEMU VMs
    inputs.home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "backup";
      home-manager.users.robie.imports = [
        inputs.nix-index-database.hmModules.nix-index
        ../hosts/<name>/home.nix
        ../modules/home/common.nix
        ../modules/home/1password.nix
        ../modules/home/bearing.nix
        ../modules/home/desktop-hyprland.nix
        # add other home modules as needed
      ];
    }
  ];
};
```

**Lab server (headless):**

```nix
<name> = mkServer {
  system = "x86_64-linux";
  modules = [
    ../hosts/<name>/configuration.nix
  ];
};
```

> **Gotcha — `vm-guest.nix`:** Include this for QEMU/KVM VMs. It enables the QEMU guest agent and SPICE support. Physical hardware does not need it.

> **Gotcha — `backupFileExtension`:** Always include `home-manager.backupFileExtension = "backup"` for desktop hosts. Without it, HM activation fails if any target file already exists as a real file (e.g. GTK config written by KDE).

**6. Build without activating**

```bash
cd ~/nixos-config
nixos-rebuild build --flake .#<name>
```

Fix any attribute errors before proceeding. See `docs/runbooks/debug-build.md`.

**7. If building on the target machine, apply**

```bash
sudo nixos-rebuild switch --flake .#<name>
```

**8. Commit**

```bash
git add hosts/<name>/ parts/nixos.nix
git commit -m "Add <name> host"
```
