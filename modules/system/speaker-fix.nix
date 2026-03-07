# TAS2781 amplifier register fix for ASUS Vivobook 14 Flip TP3407SA.
#
# The tas2781-hda driver loads firmware but doesn't properly configure the
# amplifier registers, resulting in nearly silent speakers. A oneshot service
# writes the correct register values over i2c, triggered by a timer that fires
# after PipeWire has had time to open the ALSA device.
#
# See: https://gist.github.com/rraks/4edddb99b50b94fe6298adbf3c9f43eb
# See: guides/flipper/01-speakers-fix.md

{ lib, config, pkgs, ... }:

let
  fix-speakers-script = pkgs.writeShellScript "fix-speakers" ''
    # Bail out if PipeWire hasn't started yet
    if ! ${pkgs.procps}/bin/pgrep -x pipewire > /dev/null 2>&1; then
      echo "PipeWire not running, skipping"
      exit 0
    fi

    i2c_bus=0
    i2c_addr=(0x3d 0x38)

    count=0
    for value in "''${i2c_addr[@]}"; do
        val=$((count % 2))

        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x00 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x7f 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x01 0x01
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x0e 0xc4
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x0f 0x40
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x5c 0xd9
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x60 0x10

        if [ $val -eq 0 ]; then
            ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x0a 0x1e
        else
            ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x0a 0x2e
        fi

        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x0d 0x01
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x16 0x40
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x00 0x01
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x17 0xc8
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x00 0x04
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x30 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x31 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x32 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x33 0x01

        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x00 0x08
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x18 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x19 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x1a 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x1b 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x28 0x40
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x29 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x2a 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x2b 0x00

        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x00 0x0a
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x48 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x49 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x4a 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x4b 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x58 0x40
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x59 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x5a 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x5b 0x00

        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x00 0x00
        ${pkgs.i2c-tools}/bin/i2cset -f -y "$i2c_bus" "$value" 0x02 0x00

        count=$((count + 1))
    done
  '';
in
{
  options.mySystem.speakerFix.enable =
    lib.mkEnableOption "TAS2781 speaker amplifier i2c fix";

  config = lib.mkIf config.mySystem.speakerFix.enable {

    boot.kernelModules = [ "i2c-dev" ];

    # The service just runs the i2c writes — no polling or sleeping.
    systemd.services.fix-speakers = {
      description = "Configure TAS2781 speaker amplifiers via i2c";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${fix-speakers-script}";
      };
    };

    # Timer fires 30s after boot (enough for PipeWire to open the sink)
    # and on every resume from sleep.
    systemd.timers.fix-speakers = {
      description = "Delay TAS2781 speaker fix until after PipeWire starts";
      wantedBy = [ "timers.target" "sleep.target" ];
      timerConfig = {
        OnBootSec = "30s";
        Unit = "fix-speakers.service";
      };
    };
  };
}
