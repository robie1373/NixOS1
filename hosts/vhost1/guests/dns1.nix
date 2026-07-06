# hosts/vhost1/guests/dns1.nix
#
# dns1 — primary Blocky resolver, as a microVM guest of vhost1.
# all-nixos-lab rung 5 / Phase B3. Reprovision-never-migrate (D1): replaces the
# old dns1 Proxmox VM (VMID 112, pve) with a declarative microVM. Blocky is
# stateless (D10) — no state to restore; the flake is the whole truth.
#
# Direct analog of hosts/vhost2/guests/dns2.nix (the proven rung-4 pattern); the
# only differences are identity (.20.53, dns1) and dohPort 8443 (dns1 fronts the
# roaming-DoH edge; dns2 doesn't). Because dns2 already runs on vhost2, DNS
# survives the whole vhost1 window on the cross-node pair — dns1 is the easiest,
# lowest-risk guest to bring up first (spec B3 bring-up order).
#
# Passed to the host as `microvm.vms.dns1.config` (see ../configuration.nix).

{ inputs, config, lib, pkgs, ... }:

let
  # Locally-administered MAC (02: prefix). Mnemonic: VLAN 20, host octet 53.
  mac = "02:00:00:00:20:53";
in
{
  imports = [
    ../../../modules/_system/server-common.nix   # ssh, agenix, observability agent, nix pinning
    ../../../modules/_system/blocky.nix           # the resolver (shared localDns map)
  ];

  networking.hostName = "dns1";

  # ── microVM runtime ──────────────────────────────────────────────────────────
  microvm = {
    hypervisor = "qemu";              # D4 — uniform hypervisor across guests
    vcpu = 1;
    mem  = 2560;                      # ~old 1–2 GB VM; NOT exactly 2048 (QEMU hangs
                                      # at exactly 2 GB — microvm.nix issue #171)

    # D8 — share the host store read-only; guest keeps only a writable overlay.
    shares = [{
      source     = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag        = "ro-store";
      proto      = "virtiofs";
    }];

    # Single NIC as a tap; the host attaches vm-dns1 to br0 on VLAN 20.
    interfaces = [{
      type = "tap";
      id   = "vm-dns1";
      inherit mac;
    }];
  };

  # ── Guest networking: static .20.53 on VLAN 20, matched by MAC ────────────────
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = mac;
    address = [ "192.168.20.53/24" ];
    routes  = [ { Gateway = "192.168.20.254"; } ];
  };
  networking.nameservers = [ "192.168.20.254" "1.1.1.1" ];

  # ── The resolver ──────────────────────────────────────────────────────────────
  mySystem.blocky = {
    enable = true;
    # DoH listener (self-signed, internal) behind the nginx mTLS edge for the
    # roaming endpoint. Carried from the old dns1 VM. Reachable on VLAN 20.
    dohPort = 8443;
  };
  # blocky must own :53. useNetworkd pulls in systemd-resolved, which grabs :53 on
  # the loopback stub and makes blocky's 0.0.0.0:53 bind fail. The old dns1 VM used
  # scripted networking so resolved was never on; the microVM does — force it off.
  # (Exact rung-4 dns2 gotcha, banked in proxmox-to-microvm.md Phase B2.)
  services.resolved.enable = false;

  # ── microVM boot overrides (see vhost2 dns2.nix) ──────────────────────────────
  # server-common assumes a disk-booting host (systemd-boot + growPartition); a
  # microVM boots a supplied kernel/initrd with no ESP/growable partition.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.growPartition = lib.mkForce false;

  # No Tailscale on a hypervisor guest (tailnet being decommissioned; nothing
  # load-bearing may depend on it). DNS is served on the LAN IP, so no loss.
  services.tailscale.enable = lib.mkForce false;

  system.stateVersion = "25.05";
}
