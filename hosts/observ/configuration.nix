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
  networking.nameservers = [ "192.168.20.53" "192.168.20.254" ];

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
