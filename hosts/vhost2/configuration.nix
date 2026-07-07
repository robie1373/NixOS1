# hosts/vhost2/configuration.nix
#
# vhost2 — NixOS + microvm.nix hypervisor (all-nixos-lab rung 4).
# Formerly pve2 (Proxmox). Converted in place; the flake is now the entire truth
# for this host AND its guests. See ledger proxmox-to-microvm.md Phase B2.
#
# Hardware: Intel i5-4590 (Haswell), 16 GB, Samsung 840 PRO 238 GB SSD, UEFI.
# Mgmt IP: 192.168.20.41/24 (VLAN 20), gateway 192.168.20.254  |  name: vhost2
#   (Was 192.168.7.159 untagged VLAN 10. Moved to VLAN 20 2026-07-05 — Robie's call:
#    the vhosts sat on VLAN 10 only because they predate the VLANs; hypervisor mgmt
#    belongs on VLAN 20 with the workloads. Smoke test for the same move on vhost1.)
#
# Role: runs its services as declarative microVMs (D1 reprovision-never-migrate),
# NOT on the host. Post-Project-A residents to recreate as microVMs at Phase B2
# step 5: dns2 (VLAN 20, .20.54) -> pages (VLAN 20, .20.57) -> omada (VLAN 20).
# Guest defs are added here one at a time, verified individually. None yet — this
# is the B0 host skeleton.

{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    ../../modules/_system/server-common.nix   # boot, ssh, agenix, observability agent
    ../../modules/_system/hypervisor.nix       # KVM/libvirt + Podman + microvm.host
    ../../modules/_features/patch-automation.nix  # staggered patch days (ledger patch-automation.md)
    ../../modules/_features/restic.nix         # per-guest backup sets (multi-set API)
  ];

  # ── Identity ────────────────────────────────────────────────────────────────
  networking.hostName = "vhost2";

  # ── Impermanence (retrofit branch — deploy ONLY at the retrofit window) ──────
  # Same pattern as vhost1 (authored first, 2026-07-06); see ledger
  # hypervisor-impermanence.md for mechanism + loss stories (doctrine law 7).
  fileSystems."/" = {
    device  = "none";
    fsType  = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };
  fileSystems."/persist".neededForBoot = true;   # binds happen in early boot — module asserts this

  # agenix activation runs from the INITRD, before the impermanence bind-mounts
  # exist — pointing it at the bind target (/etc/ssh/...) finds nothing and every
  # secret silently fails to decrypt (found live at the 2026-07-07 retrofit drill).
  # Read the persisted key directly; /persist is mounted in initrd (neededForBoot).
  age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # No root partition to grow — / is tmpfs (server-common's growPartition fails
  # loudly on every boot otherwise; drill finding 2026-07-07).
  boot.growPartition = lib.mkForce false;

  # libvirt is unused on microvm vhosts (guests run as microvm@ qemu units, not
  # virsh domains) and its secrets-encryption oneshot fails on the ephemeral
  # /var/lib (drill finding 2026-07-07). hypervisor.nix keeps it for nixsrv1.
  virtualisation.libvirtd.enable = lib.mkForce false;

  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/ssh/ssh_host_ed25519_key"       # host identity: agenix anchor (loss story: replant from op)
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/machine-id"                      # journald identity (loss story: regenerates, cosmetic)
    ];
    directories = [
      "/var/lib/microvms"                    # guest volumes (omada class-3 from NAS restic; class-2 priced in)
      "/var/lib/nixos"                       # uid/gid maps (loss story: regenerates)
      "/var/lib/omada-backups"               # omada .cfg autobackups via virtiofs share (loss story: restic —
                                             # exercised for real 2026-07-07 after the retrofit wipe ate this
                                             # dir; ANY host-side virtiofs share dir must be listed here)
    ];
  };

  # ── Networking: VLAN-aware bridge (systemd-networkd) ─────────────────────────
  # Replaces Proxmox's vlan-aware vmbr0. The physical NIC is a trunk from the
  # switch (VLAN 10 untagged/native = host mgmt, VLAN 20 tagged = guests). br0
  # carries the host IP on the native VLAN; each microVM tap is a tagged member
  # of its VLAN. NIC matched by permanent MAC (fc:aa:14:79:e0:62 — was "nic0" on
  # pve2) so the predictable rename under NixOS can't break the match.
  #
  # ⚠️ VERIFY AT INSTALL (Phase B2 step 4): br0 up, host reachable on .7.159,
  # a VLAN-20 tap can ping a VLAN-20 peer. This bridge design is authored, not yet
  # proven on metal.
  #
  # Dropped from pve2 deliberately: the Ansible-era `192.168.1.0/24 dev vmbr0`
  # static route (legacy OPNsense LAN, IaC now torn down) and the TEMP vmbr1 OOB
  # path on nic1 (.20.250) — both were transitional scaffolding.
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
        matchConfig.PermanentMACAddress = "fc:aa:14:79:e0:62";
        networkConfig.Bridge = "br0";
        # Native VLAN 10 untagged + VLAN 20 tagged (guests). Add more VIDs here as
        # guests on other VLANs arrive.
        bridgeVLANs = [
          { PVID = 10; EgressUntagged = 10; }
          { VLAN = 20; }
        ];
      };

      # The bridge itself carries the host management IP on VLAN 20 (moved off
      # VLAN 10, 2026-07-05). br0-self is a VLAN-20 access port (PVID 20 +
      # EgressUntagged 20) — identical form to the guest taps below — so the host's
      # own traffic egresses the uplink tagged as VLAN 20, which the switch trunk
      # already carries (the guests prove that path). The uplink ("20-uplink")
      # keeps native VLAN 10 + tagged VLAN 20 unchanged; the host simply no longer
      # uses VLAN 10.
      "30-br0" = {
        matchConfig.Name = "br0";
        address = [ "192.168.20.41/24" ];
        routes  = [ { Gateway = "192.168.20.254"; } ];
        bridgeVLANs = [ { PVID = 20; EgressUntagged = 20; } ];
        linkConfig.RequiredForOnline = "routable";
      };

      # ── Guest tap ports on br0 ──────────────────────────────────────────────
      # microvm.nix creates each guest tap (vm-<name>) but does NOT bridge it —
      # the host attaches it. Each guest tap is a VLAN-20 access port: PVID 20 +
      # EgressUntagged 20 means the guest sees plain untagged L2 on VLAN 20,
      # exactly like a Proxmox vlan-aware vmbr0 net device with "VLAN Tag = 20".
      # RequiredForOnline=no so a guest that isn't up can't block host boot.
      "40-vm-dns2" = {
        matchConfig.Name = "vm-dns2";
        networkConfig.Bridge = "br0";
        bridgeVLANs = [ { PVID = 20; EgressUntagged = 20; } ];
        linkConfig.RequiredForOnline = "no";
      };
      "40-vm-pages" = {
        matchConfig.Name = "vm-pages";
        networkConfig.Bridge = "br0";
        bridgeVLANs = [ { PVID = 20; EgressUntagged = 20; } ];
        linkConfig.RequiredForOnline = "no";
      };
      "40-vm-omada" = {
        matchConfig.Name = "vm-omada";
        networkConfig.Bridge = "br0";
        bridgeVLANs = [ { PVID = 20; EgressUntagged = 20; } ];
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

  # ── SSH interactive access ───────────────────────────────────────────────────
  # server-common already installs the ansible2 automation key. Personal key added
  # here for hands-on hypervisor work.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── Hypervisor ────────────────────────────────────────────────────────────────
  # KVM/libvirt + Podman + microvm.host support. Guest microVM definitions
  # (microvm.vms.<name>) are added at Phase B2 step 5, one at a time.
  mySystem.hypervisor.enable = true;

  # ── Guest microVMs (Phase B2 step 5) ──────────────────────────────────────────
  # Fully-declarative microVMs: config is a NixOS module, the host builds + runs
  # it as microvm@<name>.service. specialArgs threads the flake `inputs` through
  # (server-common/blocky need agenix + nixpkgs rev). Order of standup at the
  # conversion window: dns2 → pages → omada. Only dns2 authored so far.
  microvm.vms.dns2 = {
    specialArgs = { inherit inputs; };
    config = import ./guests/dns2.nix;
  };
  microvm.vms.pages = {
    specialArgs = { inherit inputs; };
    config = import ./guests/pages.nix;
  };
  # omada is stateful (block volume) and, once restic is decided, will also need
  # `self` in specialArgs for restic.nix (see ./guests/omada.nix bottom note).
  microvm.vms.omada = {
    specialArgs = { inherit inputs; };
    config = import ./guests/omada.nix;
  };
  # ── Per-guest backup sets ─────────────────────────────────────────────────────
  # vhost2 is a hypervisor, so backups are keyed per hosted GUEST, not per host —
  # each stateful guest gets its own named set → its own service repo. As guests
  # are added, add a set here; they never share a pile.
  #
  # omada: the guest writes its scheduled Omada .cfg exports to a writable virtiofs
  # share sourced at /var/lib/omada-backups on THIS host (see guests/omada.nix); we
  # back that dir up with vhost2's own key — no key is planted in the guest. Secrets
  # override to the vhost2-scoped copies (byte-identical re-encryptions of omada's,
  # so it reuses omada's NAS repo → history preserved, no NAS-side change). Snapshots
  # are tagged host=vhost2 (the honest runner); the repo path is the service owner.
  mySystem.restic.backups.omada = {
    nasPath            = "tank/backups/services/omada";
    paths              = [ "/var/lib/omada-backups" ];
    sshKeySecret       = "restic-backup-vhost2-omada";
    repoPasswordSecret = "restic-repo-password-vhost2-omada";
  };

  # ── Tailscale: OFF ────────────────────────────────────────────────────────────
  # Fleet-wide Tailscale is being decommissioned; a hypervisor must not depend on
  # it, and new hosts don't join the tailnet (dns2 precedent). server-common
  # enables the service by default — force it off here. Veto if you want it on.
  services.tailscale.enable = lib.mkForce false;

  # ── Patch automation (Robie's rulings 2026-07-06) ────────────────────────────
  # phase1 (lock-bump robot) lives HERE until clauded exists. Runs Fri+Mon nights
  # so the gate result is fresh for each set day. phase2: vhost2 = set B, Tuesday.
  # class2Volumes empty: omada is class 3 (NEVER wiped), dns2/pages stateless.
  mySystem.patchAutomation = {
    phase1 = {
      enable = true;
      onCalendar = "Fri,Mon 01:00";
      gateHosts = [ "vhost1" "vhost2" "flipper" ];
    };
    phase2 = {
      enable = true;
      onCalendar = "Tue 03:00";
      class2Volumes = [ ];
    };
  };

  system.stateVersion = "25.05";
}
