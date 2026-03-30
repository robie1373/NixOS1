{ pkgs, ... }:
{
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
  };
  users.users.robie.shell = pkgs.fish;

  programs.fish.enable = true;
  programs.git.enable  = true;

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

  programs.nh = {
    enable = true;
    flake  = "/home/robie/nixos-config";
  };

  environment.systemPackages = with pkgs; [
    disko
    nixos-anywhere
  ];
}
