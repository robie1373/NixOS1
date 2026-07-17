# hosts/vhost1/configuration.nix
#
# vhost1 — NixOS + microvm.nix hypervisor (all-nixos-lab rung 5, THE LAST PET).
# Formerly pve (Proxmox). Converted in place; the flake is the entire truth for
# this host AND its guests. See ledger proxmox-to-microvm.md Phase B3.
#
# patch-automation phase-2 first-supervised-run validation marker: 2026-07-17.
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

  # Three retrofit-drill findings from vhost2 (2026-07-07) baked in at build:
  # 1. agenix activation runs from the INITRD, before the impermanence binds —
  #    it must read the persisted key directly (else every secret silently
  #    fails to decrypt at boot; /persist IS available in initrd via neededForBoot).
  age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
  # 2. No root partition to grow — / is tmpfs; server-common's growPartition
  #    fails loudly on every boot otherwise.
  boot.growPartition = lib.mkForce false;
  # 3. libvirt is unused on microvm vhosts (guests are microvm@ qemu units) and
  #    its secrets-encryption oneshot fails on the ephemeral /var/lib.
  virtualisation.libvirtd.enable = lib.mkForce false;

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
      "40-vm-ntfy" = {
        matchConfig.Name = "vm-ntfy";
        networkConfig.Bridge = "br0";
        bridgeVLANs = [ { PVID = 20; EgressUntagged = 20; } ];
        linkConfig.RequiredForOnline = "no";
      };
      "40-vm-observ" = {
        matchConfig.Name = "vm-observ";
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
  mySystem.hypervisor.enable = true;

  # ── Guest microVMs ────────────────────────────────────────────────────────────
  # Fully-declarative microVMs: config is a NixOS module, the host builds + runs it
  # as microvm@<name>.service. specialArgs threads the flake `inputs` through
  # (server-common/blocky need agenix + nixpkgs rev). Only dns1 authored so far.
  microvm.vms.dns1 = {
    specialArgs = { inherit inputs; };
    config = import ./guests/dns1.nix;
  };
  # rung-5 guests — AUTHORED 2026-07-16 (Fable 5, prep session). Volume classes
  # per new-service-protocol appendix pre-classification; license at the rung-5
  # review. The old TODO's Tailscale questions live ON each guest file now
  # (ntfy = the load-bearing one: phone-subscription URL + cert must be decided
  # BEFORE migration — see guests/ntfy.nix header).
  microvm.vms.ntfy = {
    specialArgs = { inherit inputs; };
    config = import ./guests/ntfy.nix;
  };
  # langlab: OUT of rung 5 (Robie, 2026-07-16) — "problem vibes"; not currently
  # used; VM shut down, redesign queued in TASKS.md. Its NAS restic repo
  # (tank/backups/services/langlab, study.db) is the survival path.
  microvm.vms.observ = {
    specialArgs = { inherit inputs; };
    config = import ./guests/observ.nix;
  };

  # ── Host-staged guest secrets — activates once the KEY CEREMONY re-keys the
  # four secrets to the vhost1 recipient (agenix -r; ledger vhost1-conversion.md).
  # Guests hold no agenix (doctrine; keys churn): the host decrypts the SAME
  # .age files (vhost1 added as recipient — no -vhost1 copies needed) and stages
  # read-only virtiofs shares; guests mkForce their consumer paths to the share.
  age.secrets = {
    ntfy-admin-password.file = ../../secrets/ntfy-admin-password.age;
    ntfy-alert-topic.file    = ../../secrets/ntfy-alert-topic.age;
    snmp-config.file         = ../../secrets/snmp-config.age;
    grafana-admin-pass.file  = ../../secrets/grafana-admin-pass.age;
  };
  systemd.services.guest-secrets-stage = {
    description = "Stage decrypted guest secrets for virtiofs shares";
    wantedBy = [ "multi-user.target" ];
    before   = [ "microvms.target" ];
    after    = [ "agenix.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    # Secrets land 0400 root by default. Two consumers read their secret as a
    # NON-root user in the guest and so need 0444 (Robie's ruling 2026-07-17,
    # option 2 — surgical, not blanket): grafana (static user `grafana`) reads
    # grafana-admin-pass; snmp_exporter (DynamicUser `snmp-exporter`) reads
    # snmp-config. World-readable only WITHIN each single-purpose LAN guest where
    # only root has a shell → negligible real exposure. ntfy-admin-password stays
    # 0400 (its consumer runs as root) and ntfy-alert-topic stays 0400 (read by a
    # root helper, not the alertmanager uid).
    script = ''
      umask 077
      mkdir -p /var/lib/guest-secrets/ntfy /var/lib/guest-secrets/observ
      install -m 0400 ${config.age.secrets.ntfy-admin-password.path} /var/lib/guest-secrets/ntfy/ntfy-admin-password
      install -m 0400 ${config.age.secrets.ntfy-alert-topic.path}    /var/lib/guest-secrets/observ/ntfy-alert-topic
      install -m 0444 ${config.age.secrets.snmp-config.path}         /var/lib/guest-secrets/observ/snmp-config
      install -m 0444 ${config.age.secrets.grafana-admin-pass.path}  /var/lib/guest-secrets/observ/grafana-admin-pass
    '';
  };
  # patchAutomation.phase2.class2Volumes (when phase2 is enabled here) — ntfy
  # LICENSED class 2 (Robie, 2026-07-16):
  #   [ { guest = "ntfy"; image = "/var/lib/microvms/ntfy/ntfy-cache.img"; } ]
  # observ's volumes (also licensed) are deliberately NOT listed — monthly-wipe
  # exception mechanism doesn't exist yet; wipe manually (see guests/observ.nix).

  # ── Tailscale: OFF (host) ─────────────────────────────────────────────────────
  # A hypervisor must not depend on the tailnet. server-common enables it by
  # default — force off here (vhost2/dns2 precedent).
  services.tailscale.enable = lib.mkForce false;

  # ── Patch automation (phase 2: this host's set day) ─────────────────────────
  # ENABLED 2026-07-17 (Opus 4.8): patch-deploy-key.age exists + vhost1 is a
  # recipient; ntfy/observ class-2 volumes licensed + rehydration-tested (Gate D
  # passed both). Set day: vhost1 = Saturday (set A); vhost2 = Tuesday (set B) —
  # redundant pairs straddle sets so a bad bump can't take both DNS/observ at once.
  # class2Volumes: ntfy-cache + BOTH observ volumes, all WEEKLY (Robie's ruling
  # 2026-07-17 — no monthly exception; observ's volume is class 2 and gets wiped
  # like any other. The wipe is discipline-enforcement, not disk management; observ
  # is a current-time-diagnosis tool by design, historic data is a bonus. See
  # [[stateless-doctrine]] "defense stack" + guests/observ.nix).
  mySystem.patchAutomation.phase2 = {
    enable = true;
    onCalendar = "Sat 03:00";
    class2Volumes = [
      { guest = "ntfy";   image = "/var/lib/microvms/ntfy/ntfy-cache.img"; }
      { guest = "observ"; image = "/var/lib/microvms/observ/observ-vm.img"; }
      { guest = "observ"; image = "/var/lib/microvms/observ/observ-vl.img"; }
    ];
  };

  system.stateVersion = "25.05";
}
