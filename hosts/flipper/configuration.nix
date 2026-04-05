{ config, pkgs, self, ... }:

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

  # ── claude-code version pin ─────────────────────────────────────────────────
  # nixpkgs occasionally pins a claude-code version that doesn't exist on npm.
  # The overlay is a no-op when nixpkgs ships a working version — it only
  # activates for versions in brokenVersions. After a flake update, if claude
  # breaks again: add the bad version to brokenVersions, update pinVersion and
  # pinHash to a known-good one.
  # Accessing prev.claude-code.version inside a NixOS overlay causes infinite
  # recursion via nixpkgs's by-name-overlay.nix — so the version check must be
  # unconditional. After a flake update: if claude-code builds fine, remove this
  # overlay. If it breaks again, update pinVersion and pinHash.
  # Known broken: 2.1.88
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.overrideAttrs (old: rec {
        version = "2.1.77";
        src = prev.fetchzip {
          url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
          hash = "sha256-3bsFS3EZYbU8htlO7QtA9Qs8xlm0ZPz02bJ3ROZaugY=";
        };
        postPatch = ''
          cp ${./claude-code-2.1.77-package-lock.json} package-lock.json
          substituteInPlace cli.js \
            --replace-fail '#!/bin/sh' '#!/usr/bin/env sh'
        '';
        npmDeps = prev.fetchNpmDeps {
          inherit src postPatch;
          name = "claude-code-${version}-npm-deps";
          hash = "sha256-spxAd9PEGRQFiGjaNRqGCu23PdmfwmBQyhT+gwTiTMs=";
        };
      });
    })
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

  # Add local scripts and apps to the path
  environment.sessionVariables.PATH = [ 
    "/home/robie/languages/study" 
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
  # Replace the fish installed by programs.fish.enable with the wrapped fish.
  # /run/current-system/sw/bin/fish then points to the wrapper, so the login
  # shell (/etc/passwd) and /etc/shells both work without any extra changes —
  # programs.fish.enable handles all of that using the package we specify here.
  programs.fish.package = self.packages.${pkgs.stdenv.hostPlatform.system}.fish;

  system.stateVersion = "25.11";
}
