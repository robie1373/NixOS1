{ config, pkgs, ... }: {
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
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable GVfs (virtual filesystem daemon for network shares, MTP, etc.)
  services.gvfs.enable = true;

  # Keyring — persists secrets (SSH keys, op CLI session, browser passwords)
  # across reboots. Without this, 1Password CLI and SSH agent lose their
  # sessions on every restart and require manual re-authentication.
  services.gnome.gnome-keyring.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = false;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.robie = {
    isNormalUser = true;
    description = "Robie";
    extraGroups = [ "networkmanager" "wheel" "video" "input" ];
    initialPassword = "changeme";
    packages = with pkgs; [
    #  kdePackages.kate
    ];
  };
  users.users.robie.shell = pkgs.fish;

  #enable fish shell 
  programs.fish.enable = true;
  programs.git.enable = true;

  # Install neovim and make it the deafult editor system-wide
  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;

  # Allow robie to reboot/poweroff without interactive polkit auth.
  # Required for remote reboot via SSH (e.g. fleet update script).
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.freedesktop.login1.reboot" ||
           action.id == "org.freedesktop.login1.power-off") &&
          subject.user == "robie") {
        return polkit.Result.YES;
      }
    });
  '';

  # Install tailscale
  services.tailscale.enable = true;

  # Allow unfree packages
  # nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
    "1password"
    "1password-gui"
  ];

  nix.settings.experimental-features = ["nix-command" "flakes" ];

  programs.nh = {
    enable = true;
    flake = "/home/robie/nixos-config";
  };

  environment.systemPackages = with pkgs; [
    disko
    nixos-anywhere
  ];








}
