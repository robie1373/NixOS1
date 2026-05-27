# modules/packages.nix
#
# Package outputs for lab tooling. Currently produces the Proxmox golden bootstrap
# image used to provision new NixOS VMs without any manual console interaction.
#
# Rewrite note: this file is entirely lab-infrastructure concern — no desktop, no
# home-manager, no user configuration. Safe to keep as-is or split into a dedicated
# lab flake during the rewrite. Desktop-focused flake can omit this entirely.
#
# Build the bootstrap image:
#   nix build .#proxmox-bootstrap
#   result/nixos.vma.zst  ← import this into Proxmox as template VMID 9001
#
# After import, mark the VM as a template in Proxmox UI.
# New hosts: clone 9001 → assign VMID + IP → start → nixos-anywhere.

{ inputs, lib, ... }:

let
  # ansible2 automation key — baked into the bootstrap image so Director (and manual
  # provisioning) can SSH in as root immediately after the VM boots.
  # This is a PUBLIC key — safe to commit. The private key lives in 1Password (devops/ansible2).
  # Rewrite note: if the ansible2 key ever changes, rebuild and re-import the template.
  ansibleKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr";
in
{
  # Proxmox templates are always x86_64; this output is intentionally arch-specific.
  flake.packages.x86_64-linux.proxmox-bootstrap = inputs.nixos-generators.nixosGenerate {
    system = "x86_64-linux";

    # proxmox format produces a .vma.zst file ready for `qmrestore` or Proxmox UI import
    format = "proxmox";
    # REWRITE NOTE: nixos-generators is deprecated as of NixOS 25.05 — its functionality
    # has been upstreamed into nixpkgs. Migrate this to the native nixpkgs image API:
    #   (nixpkgs.lib.nixosSystem { modules = [ config "${nixpkgs}/nixos/modules/image/proxmox.nix" ]; })
    #   .config.system.build.proxmoxImage
    # The nixos-generators flake still works but will eventually be removed.

    modules = [{
      # Root SSH access via ansible2 key only — no password auth ever
      users.users.root.openssh.authorizedKeys.keys = [ ansibleKey ];

      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";  # key auth only, no root password login
          PasswordAuthentication = false;
        };
      };

      # qemu-guest-agent: enables Proxmox to communicate with the VM (shutdown signals,
      # IP reporting, freeze/thaw for snapshots). Required for clean Proxmox integration.
      services.qemuGuest.enable = true;

      # Firewall disabled in bootstrap image — this system is ephemeral (replaced entirely
      # by nixos-anywhere) and lives only on the trusted lab network during provisioning.
      # The real host config (in nixos-config#<hostname>) enables its own firewall.
      networking.firewall.enable = false;

      # DHCP on all interfaces — bootstrap VM needs an IP so nixos-anywhere can
      # connect. The real host config sets a static IP; this is throwaway state.
      # lib.mkForce required: proxmox-image.nix sets useDHCP = false internally.
      networking.useDHCP = lib.mkForce true;

      # Explicit disk size — suppresses deprecation warning from proxmox image module
      # (proxmox.qemuConf.diskSize was renamed to virtualisation.diskSize).
      # 4GB is sufficient for a bootstrap image; the real host gets its own disko layout.
      virtualisation.diskSize = 4 * 1024;

      # stateVersion for the bootstrap system itself. This value is irrelevant in practice
      # because nixos-anywhere wipes the disk and installs fresh from the target flake attr.
      # Set to current stable to suppress warnings.
      system.stateVersion = "25.05";
    }];
  };
}
