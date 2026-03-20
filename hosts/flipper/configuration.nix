{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "flipper";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  mySystem.audio.enable           = true;
  #mySystem.desktopKde.enable      = false;
  mySystem.desktopHyprland.enable = true;
  mySystem.nas.enable             = true;
  mySystem.speakerFix.enable      = true;
  mySystem.gaming.enable	  = true;

  # Resume device for hibernate — swap is unencrypted; label set by disko
  # (disk name "main" + partition name "swap" → "disk-main-swap")
  boot.resumeDevice = "/dev/disk/by-partlabel/disk-main-swap";

  # ── Disk encryption ────────────────────────────────────────────────────────
  # systemd initrd is required for systemd-cryptenroll (TPM2 + FIDO2 unlock).
  # After first boot, enroll additional slots — see guides/flipper/03-disk-encryption.md
  boot.initrd.systemd.enable = true;

  # TPM2 userspace tools and kernel interface
  security.tpm2.enable = true;
  security.tpm2.pkcs11.enable = true;
  security.tpm2.tctiEnvironment.enable = true;

  # FIDO2 YubiKey unlock at boot — tells systemd-cryptsetup to try FIDO2
  # and ensures the USB HID driver is in the initrd so the key is detected
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [ "fido2-device=auto" ];
  boot.initrd.kernelModules = [ "usbhid" ];

  environment.systemPackages = with pkgs; [
    wget
    tree
    terraform
    ansible
    btop
  ];

  # Enable CUPS to print documents.
  services.printing.enable = false;

  # Fix internal speakers — see guides/flipper/01-speakers-fix.md
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
