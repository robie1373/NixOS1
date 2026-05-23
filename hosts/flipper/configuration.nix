{ config, pkgs, lib, self, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/_features/net-speed.nix
  ];

  networking.hostName = "flipper";

  hardware.enableRedistributableFirmware = true;
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
  # Removed 2026-05-07: nixpkgs now at 2.1.112 which appears to build cleanly.
  # The 2.1.77 pin was added because 2.1.88 was broken on npm; 2.1.77 itself
  # later broke (cli.js missing in patchPhase) after a nixpkgs update changed
  # the package structure. If claude-code breaks again after a flake update,
  # re-add the overlay using docs/runbooks/pin-broken-package.md.
  # Known broken: 2.1.88, 2.1.77 (post-26.05 structure change)

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
    ollama		# CLI client — server runs on fivenix (see OLLAMA_HOST below)
    calibre		# eBook manager
  ];

  # Add local scripts and apps to the path
  environment.sessionVariables.PATH = [
    "/home/robie/languages/"
  ];

  # Point ollama CLI at fivenix's GPU server so `ollama run` works without flags.
  environment.sessionVariables.OLLAMA_HOST = "http://192.168.7.137:11434";

  services.printing.enable = lib.mkForce true;

  services.openssh.enable = true;
# Optional: Customize other settings
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.PasswordAuthentication = true;

  security.pam.services.sshd.startSession = true;

# iPhone mounting via ifuse
  # usbmuxd handles the USB pairing layer; ifuse mounts the filesystem.
  # udev rules trigger systemd user services on plug/unplug.
  # ENV{DEVTYPE}=="usb_device" ensures only the device event fires, not each USB interface.
  services.usbmuxd.enable = true;
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="05ac", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="ifuse-mount.service"
    SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="05ac", ACTION=="remove", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="ifuse-unmount.service"
    # GL9750 SD card reader: disable D3cold so the driver can always talk to it
    # after suspend/resume. Without this the chip wakes in D3cold (all registers
    # 0xffff) and sdhci-pci's reset never completes. See docs/flipper/README.md.
    ACTION=="add", SUBSYSTEM=="pci", ENV{PCI_ID}=="17A0:9750", ATTR{d3cold_allowed}="0"
  '';

  # Safety net: if the GL9750 still ends up in D3cold after resume (e.g. first
  # boot before the udev rule fires, or a firmware-driven transition), rebind
  # the sdhci-pci driver to force a clean reprobe. If it fell off the bus
  # entirely, rescan the parent bridge (00:1c.4 → bus 2c).
  powerManagement.resumeCommands = ''
    # Power the BT controller back on after suspend/hibernate.
    # USB BT goes to Powered=false on suspend; bluez does not re-set it on resume.
    # Use btmgmt (kernel mgmt socket) rather than bluetoothctl — bluetoothctl 5.86
    # has a regression where its list/power commands silently return exit 0 with
    # no effect. btmgmt talks straight to the kernel and is reliable.
    ${pkgs.bluez}/bin/btmgmt power on

    if [ -d /sys/bus/pci/devices/0000:2c:00.0 ]; then
      if [ "$(cat /sys/bus/pci/devices/0000:2c:00.0/power_state 2>/dev/null)" = "D3cold" ]; then
        echo 0 > /sys/bus/pci/devices/0000:2c:00.0/d3cold_allowed
        echo 0000:2c:00.0 > /sys/bus/pci/drivers/sdhci-pci/unbind 2>/dev/null || true
        sleep 1
        echo 0000:2c:00.0 > /sys/bus/pci/drivers/sdhci-pci/bind
      fi
    else
      echo 1 > /sys/bus/pci/devices/0000:00:1c.4/rescan
    fi
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

  # ── Restic backups ───────────────────────────────────────────────────────────
  mySystem.restic = {
    enable  = true;
    nasPath = "tank/backups/laptops/linux/flipper";
    paths   = [ "/home/robie" ];
    exclude = [
      "/home/robie/tmp-nas"   # staging area for NAS migration — large, not worth backing up
      "/home/robie/nas"       # NFS automount — NAS data, not a local backup target
    ];
  };

  system.stateVersion = "25.11";
}
