{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "flipper";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # ── Power management ────────────────────────────────────────────────────────
  # Swap is 16G (= RAM) — sufficient for hibernate. resumeDevice tells the
  # kernel where to find the saved image. Label is set by disko:
  # disk name "main" + partition name "swap" → "disk-main-swap".
  boot.resumeDevice = "/dev/disk/by-partlabel/disk-main-swap";

  # Lid close → hybrid-sleep (writes RAM to swap AND suspends to RAM).
  # Fast resume if power survived; falls back to swap image if it didn't.
  # Use hybrid-sleep on both battery and AC for consistent behaviour.
  services.logind.settings.Login.HandleLidSwitch             = "hybrid-sleep";
  services.logind.settings.Login.HandleLidSwitchExternalPower = "hybrid-sleep";

  # Critical battery → hibernate (swap only — don't trust RAM at near-zero power).
  services.upower = {
    enable               	= true;
    criticalPowerAction  	= "Hibernate";
    percentageLow 		= 20;
    percentageCritical		= 10;
    percentageAction		= 5;
    usePercentageForPolicy	= true;
  };

  # See docs/flipper/04-power-management.md for full design notes and
  # the known unencrypted-swap security tradeoff.

  # ── Disk encryption ────────────────────────────────────────────────────────
  # systemd initrd is required for systemd-cryptenroll (TPM2 + FIDO2 unlock).
  # After first boot, enroll additional slots — see docs/flipper/03-disk-encryption.md
  boot.initrd.systemd.enable = true;

  # TPM2 userspace tools and kernel interface
  security.tpm2.enable = true;
  security.tpm2.pkcs11.enable = true;
  security.tpm2.tctiEnvironment.enable = true;

  # FIDO2 YubiKey unlock at boot — tells systemd-cryptsetup to try FIDO2
  # and ensures the USB HID driver is in the initrd so the key is detected.
  # pcsclite.lib is added to the initrd store because systemd-cryptsetup
  # tries to dlopen() libpcsclite_real.so.1 at runtime; without it the FIDO2
  # path fails silently and falls through to TPM2 PIN. See NixOS issue #329135.
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [ "fido2-device=auto" ];
  boot.initrd.kernelModules = [ "usbhid" ];
  # NixOS includes libcryptsetup-token-systemd-tpm2.so automatically when TPM2 is
  # configured, but does NOT include the FIDO2 equivalent. We add it manually along
  # with libfido2 (dloaded at runtime by libsystemd-shared) and pcsclite (dloaded
  # by systemd-cryptsetup for smart card paths). Without these, FIDO2 unlock silently
  # falls through to TPM2 PIN with no prompt. See NixOS issue #329135.
  boot.initrd.systemd.storePaths = [
    pkgs.pcsclite.lib
    pkgs.libfido2
    "${config.boot.initrd.systemd.package}/lib/cryptsetup/libcryptsetup-token-systemd-fido2.so"
  ];

  environment.systemPackages = with pkgs; [
    wget
    tree
    terraform
    ansible
    btop
    ripgrep
    ifuse 		# for mounting iphone
    libimobiledevice  	# for mounting iphone
    bambu-studio
  ];

  # Enable CUPS to print documents.
  services.printing.enable = false;

  services.openssh.enable = true;
# Optional: Customize other settings
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.PasswordAuthentication = true;

# iPhone mounting via ifuse
  # usbmuxd handles the USB pairing layer; ifuse mounts the filesystem.
  # udev rules trigger systemd user services on plug/unplug.
  # ENV{DEVTYPE}=="usb_device" ensures only the device event fires, not each USB interface.
  services.usbmuxd.enable = true;
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="05ac", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="ifuse-mount.service"
    SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="05ac", ACTION=="remove", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="ifuse-unmount.service"
  '';

  # Fix internal speakers — see docs/flipper/01-speakers-fix.md
  hardware.firmware = [
    (pkgs.runCommand "tas2781-firmware-fix" {} ''
      mkdir -p $out/lib/firmware
      cp ${pkgs.linux-firmware}/lib/firmware/TAS2XXX10A40.bin \
        $out/lib/firmware/TAS2XXX10A4.bin
    '')
  ];

  # Set to the NixOS release you first installed this system with.
  # Do not change this after the first install.
  system.stateVersion = "25.11";
}
