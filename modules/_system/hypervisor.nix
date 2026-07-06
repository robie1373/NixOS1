# modules/_system/hypervisor.nix
#
# Baseline for a NixOS host that runs VMs, microVMs, and containers.
# Imported by the bare-metal hypervisors (nixsrv1, vhost1, vhost2). Does NOT
# import server-common — that's separate (but the importing host does, which is
# where agenix comes from; the console-recovery secret below relies on it).
#
# KVM/libvirt: full VM management via virsh.
# Podman: rootless-capable containers (dockerCompat alias provided).
# microvm.nix: lightweight type-1 VMs — requires microvm flake input in
#              the host's nixosConfigurations declaration (see modules/hosts/nixsrv1/default.nix).
#
# Individual microVM definitions live in the importing host config, not here.

{ config, pkgs, lib, ... }:

{
  options.mySystem.hypervisor = {
    enable = lib.mkEnableOption "KVM/libvirt + Podman + microvm.nix hypervisor stack";
  };

  config = lib.mkIf config.mySystem.hypervisor.enable {

    # ── KVM / libvirt ─────────────────────────────────────────────────────
    virtualisation.libvirtd = {
      enable         = true;
      qemu.runAsRoot = false;
    };

    # ── Podman ────────────────────────────────────────────────────────────
    virtualisation.podman = {
      enable       = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    # ── microvm.nix host support ──────────────────────────────────────────
    # Enables host infrastructure for launching microVMs.
    # The microvm flake input must be in the host module declaration.
    microvm.host.enable = true;

    # ── Kernel modules ────────────────────────────────────────────────────
    boot.kernelModules = [ "kvm-intel" ];

    # ── Packages ──────────────────────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      virtiofsd
      qemu_kvm
    ];

    # ── User access ───────────────────────────────────────────────────────
    users.users.root.extraGroups = [ "libvirtd" "kvm" ];

    # ── Console-recovery root password ────────────────────────────────────
    # Break-glass login at the JetKVM/physical console when a host is up but
    # unreachable — the locked-root trap we dodged on the vhost2 conversion
    # (Robie, 2026-07-05). Declarative + secret-managed: the sha-512 hash is an
    # agenix secret decrypted at boot by the host key; the plaintext lives ONLY
    # in 1Password (devops/"Hypervisor root recovery (fleet)"). Scoped here on
    # purpose — hypervisor.nix is imported only by the bare-metal hosts that
    # actually have a console; the microVM guests (which import server-common,
    # not this) are correctly excluded. SSH stays key-only (server-common sets
    # PermitRootLogin=prohibit-password + PasswordAuthentication=false), so this
    # password is usable at the console ONLY, never over the network.
    # Recipients are `hypervisors` in secrets/secrets.nix; add a new host there
    # and re-key when it joins (vhost1 at its rung-5 host-key ceremony).
    age.secrets.root-recovery.file = ../../secrets/root-recovery.age;
    users.users.root.hashedPasswordFile = config.age.secrets.root-recovery.path;

    # A declarative password is ONLY applied to an existing user when mutableUsers
    # is false — nixpkgs update-users-groups.pl line ~300:
    #   $sp_pwdp = $u->{hashedPassword} if defined ... && !$spec->{mutableUsers};
    # With the default mutableUsers=true, root (created Locked at install) keeps its
    # `!` and hashedPasswordFile is silently ignored (verified on vhost2 2026-07-05).
    # These hypervisors have no imperative users (root only, key-managed), so making
    # them fully declarative is correct AND is what makes the recovery password take.
    # Safe with agenix: age.nix sets `users.deps = [ "agenixInstall" ]`, so the secret
    # is decrypted before the users script reads it (no lock-out-on-boot race).
    users.mutableUsers = false;
  };
}
