# hosts/vhost2/guests/dns2.nix
#
# dns2 — secondary Blocky resolver, as a microVM guest of vhost2.
# all-nixos-lab rung 4 / Phase B2 step 5. Reprovision-never-migrate (D1): this
# replaces the old dns2 Proxmox VM (VMID 113) with a declarative microVM. Blocky
# is stateless (D10) — no state to restore; the flake is the whole truth.
#
# Passed to the host as `microvm.vms.dns2.config` (see ../configuration.nix).
# The microvm.nix guest module (nixos-modules/microvm) is merged in automatically
# by the host's microvm.vms submodule, so microvm.* options are available here.
#
# Networking model (D5): a single tap ("vm-dns2") created by microvm.nix and
# attached by the HOST to br0 as a VLAN-20 access port (bridgeVLANs PVID 20). The
# guest therefore sees a plain untagged L2 link on VLAN 20 and matches its NIC by
# MAC to take the static .20.54 address — unchanged from the old VM.
#
# Store sharing (D8): host /nix/store mounted read-only over virtiofs; the guest
# adds only its writable overlay. Big RAM/disk win on the 16 GB node.

{ inputs, config, lib, pkgs, ... }:

let
  # Locally-administered MAC (02: prefix). Mnemonic: VLAN 20, host octet 54.
  mac = "02:00:00:00:20:54";
in
{
  imports = [
    ../../../modules/_system/server-common.nix   # ssh, agenix, observability agent, nix pinning
    ../../../modules/_system/blocky.nix           # the resolver (shared localDns map)
  ];

  networking.hostName = "dns2";

  # ── microVM runtime ──────────────────────────────────────────────────────────
  microvm = {
    hypervisor = "qemu";              # D4 — uniform hypervisor across guests
    vcpu = 1;
    mem  = 2560;                      # ~old 2 GB VM, but NOT exactly 2048: QEMU hangs
                                      # at exactly 2 GB (microvm.nix issue #171)

    # D8 — share the host store read-only; guest keeps only a writable overlay.
    shares = [{
      source     = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag        = "ro-store";
      proto      = "virtiofs";
    }];

    # Single NIC as a tap; the host attaches vm-dns2 to br0 on VLAN 20.
    interfaces = [{
      type = "tap";
      id   = "vm-dns2";
      inherit mac;
    }];
  };

  # ── Guest networking: static .20.54 on VLAN 20, matched by MAC ────────────────
  # microvm.optimize enables systemd-networkd in the guest; match the NIC by MAC
  # (interface name is not stable across virtio enumeration) and pin the address.
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = mac;
    address = [ "192.168.20.54/24" ];
    routes  = [ { Gateway = "192.168.20.254"; } ];
  };
  # Blocky is the resolver; the host itself resolves via public DNS. dns2's own
  # stub resolver points at the gateway + public fallback (same as the old VM).
  networking.nameservers = [ "192.168.20.254" ];   # gateway-only (Robie policy 2026-07-21); no 1.1.1.1

  # ── The resolver ──────────────────────────────────────────────────────────────
  mySystem.blocky.enable = true;
  # blocky must own :53. useNetworkd (above) pulls in systemd-resolved, which grabs
  # :53 on the loopback stub and makes blocky's 0.0.0.0:53 bind fail
  # ("address already in use"). The old dns2 VM used scripted networking so resolved
  # was never enabled; the microVM does, so turn it off explicitly.
  services.resolved.enable = false;

  # ── microVM boot overrides ────────────────────────────────────────────────────
  # server-common assumes a disk-booting host (systemd-boot + growPartition). A
  # microVM boots a supplied kernel/initrd directly and has no ESP or growable
  # partition — force those off so the guest evaluates cleanly.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;

  # No Tailscale on a hypervisor guest (dns2 precedent; the tailnet is being
  # decommissioned and nothing load-bearing may depend on it).
  services.tailscale.enable = lib.mkForce false;

  # Guests do NOT embed the nixos-config git rev (server-common sets it from
  # inputs.self.rev). With it, EVERY commit changes every guest closure and a
  # host switch restarts all guests — defeating per-guest restart granularity
  # (proven 2026-07-07). Hosts keep theirs; guests are identity-less anyway.
  system.configurationRevision = lib.mkForce null;

  system.stateVersion = "25.05";
}
