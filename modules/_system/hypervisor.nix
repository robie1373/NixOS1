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

    # PIN the microvm uid (Robie, 2026-08-28 — closes the audit item).
    # `microvm` OWNS /var/lib/microvms, which holds EVERY guest volume on this
    # host (ntfy-cache.img, observ-vm.img, observ-vl.img, git-repos.img). That
    # makes it a persistent-volume owner, and the rule from the 2026-07-21 git
    # break applies: pin the uid/gid of ANY user owning a persistent volume.
    # See ledger2/new-service-protocol.md "PIN the uid/gid"; guests/git.nix is
    # the reference impl.
    #
    # 999 is what it has ALREADY been allocated on both vhosts — this pin
    # records the running value, it does not change it, so no chown is needed.
    # Verified live on vhost1 and vhost2 2026-08-28 (`id microvm` → uid=999).
    #
    # Why it was not already broken, and why the pin is still worth having:
    # both vhosts persist /var/lib/nixos (impermanence allowlist), so the
    # uid-map carries "microvm":999 across the wipe and it does NOT drift on
    # reboot. The exposure is a CONFIG change — a module statically claiming
    # 999, or reordering auto-allocation — which is exactly how git broke
    # (enabling git-daemon pinned git=41, overrode the map, orphaned the
    # 999-owned repos). Low probability; blast radius is every guest volume on
    # both hypervisors at once. Declaring it makes the id ours, not the
    # allocator's.
    #
    # The GROUP needs no pin: microvm runs in `kvm`, gid 302, which is a
    # statically reserved NixOS id already.
    users.users.microvm.uid = lib.mkForce 999;

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
