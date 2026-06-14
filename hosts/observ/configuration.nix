# hosts/observ/configuration.nix
#
# Visibility stack — VictoriaMetrics + VictoriaLogs + Grafana.
# VMID: TBD  |  IP: 192.168.20.56/24  |  Node: pve  |  VLAN: 20
# Suggested Proxmox spec: 2 vCPU, 2048 MB RAM, 16 GB virtio disk, UEFI.
#
# Stores hold ~10 days of metrics + logs (short-term troubleshooting only).
# Losing this host loses visibility, not services — safe to redeploy.
#
# After provisioning (see docs/observability/build-runbook.md):
#   1. Tailscale joins automatically on first boot (auth key re-encrypted to this host).
#   2. Grafana: http://192.168.20.56:3000 (admin/admin first login).
#   3. Confirm metrics:  http://192.168.20.56:8428/vmui
#   4. Roll out the agent to other hosts (already wired in server-common) by
#      redeploying them; they ship to this host automatically.

{ inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    inputs.disko.nixosModules.disko
    ../../modules/_system/server-common.nix
    ../../modules/_system/observability.nix
    ../../modules/_system/tailscale-autoconnect.nix
    ../../modules/_features/tailscale-watchdog.nix
  ];

  # ── Identity ───────────────────────────────────────────────────────────────
  networking.hostName = "observ";

  # ── Network ────────────────────────────────────────────────────────────────
  networking.interfaces.ens18.ipv4.addresses = [{
    address      = "192.168.20.56";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.254";
  # External DNS by choice, not necessity. The VLAN 20 internal resolver is dns1
  # (192.168.20.53, Blocky); VLAN 20 can't reach the VLAN 7 Technitium hosts, and
  # the fw gateway (.254) doesn't itself forward external DNS here. observ only
  # needs external resolution (it scrapes by IP, no .home.lab lookups), so it uses
  # Cloudflare directly and avoids a hard dependency on dns1 being up — dns1 was
  # stopped during the initial deploy. Hosts that need internal names should point
  # at dns1 (.53) with an external fallback.
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

  # ── SSH ─────────────────────────────────────────────────────────────────────
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr" # ansible2
  ];

  # ── Visibility stack ────────────────────────────────────────────────────────
  mySystem.observability.enable = true;
  # pveExporter stays off until the PVE API token secret exists. Flip to true
  # and add secrets/pve-exporter-token.age to light up Proxmox metrics.
  # mySystem.observability.pveExporter.enable = true;

  system.stateVersion = "25.05";
}
