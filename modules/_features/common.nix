{ inputs, config, pkgs, ... }:
{
  imports = [
    inputs.agenix.nixosModules.default
    inputs.nix-index-database.nixosModules.nix-index
  ];
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS        = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT    = "en_US.UTF-8";
    LC_MONETARY       = "en_US.UTF-8";
    LC_NAME           = "en_US.UTF-8";
    LC_NUMERIC        = "en_US.UTF-8";
    LC_PAPER          = "en_US.UTF-8";
    LC_TELEPHONE      = "en_US.UTF-8";
    LC_TIME           = "en_US.UTF-8";
  };

  # Enable GVfs (virtual filesystem daemon for network shares, MTP, etc.)
  services.gvfs.enable = true;

  # Keyring — persists secrets (SSH keys, op CLI session, browser passwords)
  # across reboots. Without this, 1Password CLI and SSH agent lose their
  # sessions on every restart and require manual re-authentication.
  services.gnome.gnome-keyring.enable = true;

  services.printing.enable = false;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.robie = {
    isNormalUser  = true;
    description   = "Robie";
    extraGroups   = [ "networkmanager" "wheel" "video" "input" ];
    initialPassword = "changeme";
    # Track whatever fish is configured as the system fish.  On hosts that set
    # programs.fish.package = wrapped fish, this resolves to that wrapper.
    shell = config.programs.fish.package;
  };

  programs.fish.enable = true;
  programs.git.enable  = true;
  programs.git.config  = [{ user = { name = "robie1373"; email = "robie1373@gmail.com"; }; }];

  programs.nix-index-database.comma.enable = true;

  # Install neovim and make it the default editor system-wide
  programs.neovim.enable        = true;
  programs.neovim.defaultEditor = true;

  # Install tailscale
  services.tailscale.enable = true;

  # Allow 1Password (unfree). The GUI is handled by features/1password.nix
  # which sets allowUnfree = true; this predicate is belt-and-suspenders.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "1password"
    "1password-gui"
  ];

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

  # Allow robie to copy store paths from other trusted machines (e.g. nixos-rebuild
  # --target-host from flipper to fivenix). Without this, nix-daemon rejects unsigned
  # closures pushed by non-root users, breaking remote deployment.
  nix.settings.trusted-users = [ "root" "robie" ];

  # nix-ld: stub dynamic linker at /lib/ld-linux-x86-64.so.2 that allows
  # generic Linux ELF binaries (uvx-downloaded Python, VS Code extensions, etc.)
  # to execute on NixOS without patching. The uv Python distributions are
  # standalone/bundled, so no extra libraries are needed.
  programs.nix-ld.enable = true;

  programs.nh = {
    enable = true;
    flake  = "/home/robie/nixos-config";
  };

  environment.systemPackages = with pkgs; [
    disko
    nixos-anywhere
  ];
}
