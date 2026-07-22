# modules/system/server-common.nix
#
# Baseline configuration imported by every headless lab server.
# Provides: boot, SSH, networking foundation, Tailscale, agenix, timezone.
#
# What belongs here: things every lab server needs unconditionally.
# What does NOT belong here: service-specific config, static IPs (host concern),
# stateVersion (generated at install time, set in host config).
#
# Rewrite note: this module is lab-infrastructure only. No desktop, no home-manager.
# Safe to keep as-is or move to a dedicated lab flake during the rewrite.

{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    inputs.agenix.nixosModules.default
    ../_features/observability-agent.nix
  ];

  # ── Boot ────────────────────────────────────────────────────────────────────
  # systemd-boot requires UEFI. Proxmox VMs default to UEFI when SeaBIOS is not
  # explicitly selected. The disko config must include an ESP partition.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Cap boot-menu entries so old generations get pruned automatically on each
  # rebuild. Same rationale as _features/common.nix — without this, entries
  # accumulate forever. Server VMs see fewer rebuilds than desktops but the
  # ESP is small on these so the cap matters more, not less.
  boot.loader.systemd-boot.configurationLimit = 20;

  # Automatically grow the root partition and filesystem to fill available disk
  # space on boot. Allows Proxmox disk resizes (qm resize) to take effect on
  # next redeploy without any in-VM intervention.
  boot.growPartition = true;

  # ── Networking foundation ────────────────────────────────────────────────────
  # Disable DHCP globally — servers use static IPs configured per-host.
  # Each host config defines networking.interfaces.<name>.ipv4.addresses and
  # networking.defaultGateway. networkmanager is not used on servers.
  networking.useDHCP = false;
  networking.usePredictableInterfaceNames = true;

  # ── SSH ─────────────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      # Key auth only — no passwords, no root password login
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
    # Host key is pre-generated and planted by nixos-anywhere via --extra-files.
    # Private key lives in 1Password (devops/"<hostname> host SSH key").
    # Public key is committed to hosts/<hostname>/ssh_host_ed25519_key.pub
    # and used as the age recipient in secrets/secrets.nix.
    hostKeys = [{
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }];
  };

  # ansible2 automation key — allows Director and manual provisioning to SSH in.
  # Personal key (id_ed25519) is NOT included here; it goes in individual host
  # configs if interactive access is needed.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKD+F2AoDhUcKLXji5jOmPI/XduaADEs2cxAF1w/HSnr"
  ];

  # ── Observability agent ──────────────────────────────────────────────────────
  # node-exporter + Alloy log shipping to the observ visibility host. Enabled
  # fleet-wide so every lab server ships data automatically; dormant on a host
  # until its next rebuild. Degrades gracefully if observ is down (chaos-monkey).
  mySystem.observabilityAgent.enable = true;

  # Tailscale is NOT installed on lab servers/guests — flipper is the only fleet
  # machine on the tailnet (Robie, 2026-07-21). See [[tailscale-removal]].

  # ── Locale and timezone ──────────────────────────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Base packages ────────────────────────────────────────────────────────────
  # Minimal set only. Service-specific packages belong in service modules.
  environment.systemPackages = with pkgs; [
    git
    curl
    htop
    jq
  ];

  # ── Nix settings ────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Pin nix registry to a GitHub reference rather than a store path.
  # NixOS default behaviour registers flake inputs as store-path references,
  # which drags the entire nixpkgs source tree (~500 MB) into every system
  # closure — fatal on small service VMs with limited /nix/store space.
  # Using a github: reference records only the locked rev; no source in closure.
  nix.registry.nixpkgs = {
    from = { id = "nixpkgs"; type = "indirect"; };
    to = {
      type  = "github";
      owner = "NixOS";
      repo  = "nixpkgs";
      rev   = inputs.nixpkgs.rev;
    };
  };

  # ── Configuration revision ───────────────────────────────────────────────────
  # Embeds the nixos-config git revision into the running system closure.
  # Director reads this via `nixos-version --json` to detect drift:
  #   deployed rev != git HEAD of nixos-config → update needed
  # Note: self.rev is only set on clean git trees. Dirty builds produce null,
  # which Director treats as a signal that the host was deployed from uncommitted
  # state — also surfaced as drift.
  system.configurationRevision = inputs.self.rev or null;
}
