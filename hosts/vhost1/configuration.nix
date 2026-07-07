# hosts/vhost1/configuration.nix
#
# vhost1 — NixOS + microvm.nix hypervisor (all-nixos-lab rung 5, THE LAST PET).
# Formerly pve (Proxmox). Converted in place; the flake is the entire truth for
# this host AND its guests. See ledger proxmox-to-microvm.md Phase B3.
#
# Hardware: Intel i7-6700K (Skylake), 16 GB, Samsung 970 EVO Plus 1TB NVMe (boot),
# Samsung 870 EVO 2TB SATA (LEFT ALONE — not touched), UEFI.
# Mgmt IP: 192.168.20.40/24 (VLAN 20), gateway 192.168.20.254  |  name: vhost1
#   (Hypervisor mgmt on VLAN 20 with the workloads — Robie's exec decision 2026-07-05,
#    smoke-tested end-to-end on vhost2 first. NOT VLAN 10 like the old pve.)
#
# Role: runs its services as declarative microVMs (D1 reprovision-never-migrate),
# NOT on the host. Post rung-1/2 residents to recreate as microVMs at the window:
#   dns1 (VLAN 20, .20.53) · ntfy (VLAN 20, .20.10) · langlab (VLAN 20, .20.11) ·
#   observ (VLAN 20, .20.56).  [HA/105 deferred — D6, may not come up this window.]
# Bring-up order (spec B3): observ + ntfy FIRST (restore eyes/alerts after the
# blind window), then dns1, langlab.
#
# Tailscale is DEAD fleet-wide (Robie, 2026-07-05). ntfy and langlab used the tailnet
# for their access hostname + TLS cert; that's gone. They (and observ) are reached by
# LAN IP on VLAN 20 — static, unchanged addresses (.20.10 / .20.11 / .20.56). Guest
# defs are authored below in hosts/vhost1/guests/.

{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    ../../modules/_system/server-common.nix   # boot, ssh, agenix, observability agent
    ../../modules/_system/hypervisor.nix       # KVM/libvirt + Podman + microvm.host
    ../../modules/_features/restic.nix         # per-guest backup sets (multi-set API)
    ../../modules/_features/patch-automation.nix  # staggered unattended patch days (ledger patch-automation.md)
  ];

  # ── Identity ────────────────────────────────────────────────────────────────
  networking.hostName = "vhost1";

  # ── Impermanence (Robie's ruling 2026-07-06) ─────────────────────────────────
  # `/` is RAM and dies at poweroff. The attrset below is THE persist list — the
  # exhaustive statement of what this host is beyond its flake (ledger
  # hypervisor-impermanence.md; every entry needs a loss story per stateless-
  # doctrine law 7). nixos-anywhere plants the host key under /persist/etc/ssh/
  # (--extra-files path gains the /persist prefix — the ONLY runbook difference).
  # Deliberately ephemeral, no persist entry (loss story = rehydrates or nothing
  # to lose): /var/log/journal (Alloy ships to observ continuously — pending
  # Robie's journal ruling), libvirt + podman state (escape-hatch tooling, no
  # declared VMs/containers; images re-pull).
  fileSystems."/" = {
    device  = "none";
    fsType  = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };
  fileSystems."/persist".neededForBoot = true;   # binds happen in early boot — required by the module
  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/ssh/ssh_host_ed25519_key"       # host identity: agenix anchor (loss story: replant from op)
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/machine-id"                      # journald identity (loss story: regenerates, cosmetic)
    ];
    directories = [
      "/var/lib/microvms"                    # guest volumes + booted-closure pins (loss story: class-3/4 from NAS restic; class-2 priced in)
      "/var/lib/nixos"                       # uid/gid maps (loss story: regenerates, chown fixups at worst)
    ];
  };

  # ── Networking: VLAN-aware bridge (systemd-networkd) ─────────────────────────
  # Replaces Proxmox's vlan-aware vmbr0. Physical NIC "nic0" is a trunk from the
  # switch (VLAN 10 untagged/native = host mgmt on .7.x, VLAN 20 tagged = guests on
  # .20.x). br0 carries the host IP on the native VLAN; each microVM tap is a
  # tagged member of its VLAN. NIC matched by permanent MAC (1c:1b:0d:73:7c:21 —
  # was "nic0" on pve) so the predictable rename under NixOS can't break the match.
  #
  # br0-self sits on VLAN 20 (host mgmt moved off VLAN 10 — see header). Same design
  # proven on vhost2 2026-07-05: br0-self is a VLAN-20 access port; the uplink keeps
  # native VLAN 10 + tagged VLAN 20, so host traffic egresses tagged VLAN 20.
  # ⚠️ VERIFY AT INSTALL (spec B3, mirrors vhost2 B2 step 4): br0 up, host reachable
  # on .20.40, a VLAN-20 tap can ping a VLAN-20 peer. Rung-4 gotcha to expect: after
  # kexec, nixos-anywhere may loop "No route to host" because the mgmt IP was a bridge
  # IP the installer doesn't recreate — add it by hand on the JetKVM console
  # (`ip addr add 192.168.20.40/24 dev <uplink>`) to let nixos-anywhere reconnect.
  # pve's /etc/network/interfaces was clean (no legacy route / no OOB vmbr1).
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];   # host uses public DNS — never
                                                       # depends on a Blocky guest it hosts

  systemd.network = {
    enable = true;

    netdevs."10-br0" = {
      netdevConfig = { Name = "br0"; Kind = "bridge"; };
      bridgeConfig = {
        VLANFiltering = true;
        DefaultPVID   = 10;      # host/native VLAN
        STP           = false;   # single uplink, no loop
      };
    };

    networks = {
      # Physical uplink (trunk) enslaved to br0.
      "20-uplink" = {
        matchConfig.PermanentMACAddress = "1c:1b:0d:73:7c:21";
        networkConfig.Bridge = "br0";
        # Native VLAN 10 untagged + VLAN 20 tagged (guests). Add more VIDs here as
        # guests on other VLANs arrive.
        bridgeVLANs = [
          { PVID = 10; EgressUntagged = 10; }
          { VLAN = 20; }
        ];
      };

      # The bridge itself carries the host management IP on VLAN 20 (access port,
      # same form as the guest taps — proven on vhost2 2026-07-05).
      "30-br0" = {
        matchConfig.Name = "br0";
        address = [ "192.168.20.40/24" ];
        routes  = [ { Gateway = "192.168.20.254"; } ];
        bridgeVLANs = [ { PVID = 20; EgressUntagged = 20; } ];
        linkConfig.RequiredForOnline = "routable";
      };

      # ── Guest tap ports on br0 ──────────────────────────────────────────────
      # microvm.nix creates each guest tap (vm-<name>) but does NOT bridge it — the
      # host attaches it. Each guest tap is a VLAN-20 access port (PVID 20 +
      # EgressUntagged 20): the guest sees plain untagged L2 on VLAN 20, exactly
      # like a Proxmox vlan-aware vmbr0 net device with "VLAN Tag = 20".
      # RequiredForOnline=no so a guest that isn't up can't block host boot.
      "40-vm-dns1" = {
        matchConfig.Name = "vm-dns1";
        networkConfig.Bridge = "br0";
        bridgeVLANs = [ { PVID = 20; EgressUntagged = 20; } ];
        linkConfig.RequiredForOnline = "no";
      };
      # TODO(rung5): add 40-vm-ntfy / 40-vm-langlab / 40-vm-observ once their guest
      # defs are authored (pending the Tailscale fork — see header + TODO block).
    };
  };

  # ── SSH interactive access ───────────────────────────────────────────────────
  # server-common already installs the ansible2 automation key. Personal key added
  # here for hands-on hypervisor work.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── Hypervisor ────────────────────────────────────────────────────────────────
  mySystem.hypervisor.enable = true;

  # ── Guest microVMs ────────────────────────────────────────────────────────────
  # Fully-declarative microVMs: config is a NixOS module, the host builds + runs it
  # as microvm@<name>.service. specialArgs threads the flake `inputs` through
  # (server-common/blocky need agenix + nixpkgs rev). Only dns1 authored so far.
  microvm.vms.dns1 = {
    specialArgs = { inherit inputs; };
    config = import ./guests/dns1.nix;
  };

  # ── TODO(rung5) — guests pending decisions ────────────────────────────────────
  # CLASS-2 VOLUMES (if Robie licenses them — spec w/ exact sizes/mounts/cadence:
  # ledger new-service-protocol.md → Appendix): observ = split narrow volumes
  # victoriametrics 8G + victorialogs 8G (grafana ephemeral), MONTHLY wipe; ntfy =
  # ntfy-cache 1G on /var/lib/ntfy-sh, weekly wipe. Register each in
  # patchAutomation.phase2.class2Volumes or it escapes law 8.
  # ntfy (.20.10)  : state /var/lib/ntfy-sh (restic-covered). BLOCKED on the
  #                  Tailscale fork — ntfy's access URL + TLS cert ride the tailnet
  #                  today; the guest doctrine forces Tailscale off. Load-bearing
  #                  (backup alerts), so this needs a real answer, not a silent flip.
  # langlab (.20.11): state /var/lib/langlab (restic-covered). Same Tailscale
  #                  coupling as ntfy; lower stakes (interactive access).
  # observ (.20.56) : VM/VL/Grafana, state VOLATILE (no restore — Robie 2026-07-05).
  #                  Grafana is LAN-IP (:3000), likely fine Tailscale-off; CONFIRM
  #                  the Alertmanager→ntfy delivery path doesn't ride the tailnet.
  # For stateful guests (ntfy, langlab), backups likely move HOST-SIDE per the omada
  # rung-4 precedent (planting a private host key in a microVM is unproven) — that
  # becomes a `mySystem.restic.backups.<name>` set here.

  # ── Tailscale: OFF (host) ─────────────────────────────────────────────────────
  # A hypervisor must not depend on the tailnet. server-common enables it by
  # default — force off here (vhost2/dns2 precedent).
  services.tailscale.enable = lib.mkForce false;

  # ── Patch automation (phase 2: this host's set day) ─────────────────────────
  # ⛔ Enable AFTER Robie mints the git deploy key (see patch-automation.nix header)
  # and the patch-deploy-key.age secret exists for this host. Set day: vhost1 =
  # Saturday (set A); vhost2 = Tuesday (set B) — redundant pairs straddle sets.
  # class2Volumes: none yet — observ/ntfy class-2 volumes pending Robie's rung-5
  # ruling; add entries here when licensed (NEVER class-3/4 volumes).
  # mySystem.patchAutomation.phase2 = {
  #   enable = true;
  #   onCalendar = "Sat 03:00";
  #   class2Volumes = [ ];
  # };

  system.stateVersion = "25.05";
}
