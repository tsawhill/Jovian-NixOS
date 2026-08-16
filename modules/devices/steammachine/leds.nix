{ config, lib, options, pkgs, ... }:

let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    types
  ;
  cfg = config.jovian.devices.steammachine;

  # These are sysfs attributes rather than device nodes, so udev's MODE=, GROUP=,
  # OWNER= and TAG+="uaccess" do not apply to them and permissions have to be set
  # from a RUN+= helper instead.
  ledPerms = pkgs.writeShellScript "valve-leds-perms" ''
    for f in "$2"/*; do
      [ -f "$f" ] || continue
      # Writing uevent re-triggers device events; leave it to root.
      if [ "''${f##*/}" != "uevent" ]; then
        ${pkgs.coreutils}/bin/chown "$1" "$f" 2>/dev/null || true
      fi
    done
    # Never fail the udev rule over one unwritable attribute.
    exit 0
  '';

  # Steam's LED brightness slider writes brightness_scale, a global EC register
  # that the Steam Machine ignores: the driver sets it to 0 at probe while the
  # LEDs stay at full. Per-LED brightness does work, because
  # led_mc_calc_color_components() turns it into a multiplier on the RGB
  # registers. So mirror the slider onto every LED.
  brightnessMirror = pkgs.writeShellScript "valve-leds-brightness-mirror" ''
    set -u
    prev=
    while :; do
      scale=""
      for f in /sys/class/leds/valve-leds*/brightness_scale; do
        if [ -r "$f" ]; then scale="$f"; break; fi
      done

      if [ -n "$scale" ]; then
        cur=""
        read -r cur < "$scale" || cur=""
        if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
          # brightness_scale reads as hex (0xff); brightness takes 0-255.
          # Validate before converting: an arithmetic error on an unexpected
          # value unwinds the enclosing loop and would kill this service.
          val=""
          case "$cur" in
            0x*|0X*)
              hex=''${cur#0[xX]}
              case "$hex" in
                ""|*[!0-9a-fA-F]*) : ;;
                ??|?) val=$(( 16#$hex )) ;;
              esac
              ;;
            ""|*[!0-9]*) : ;;
            # Bounded by length: a value too large for the shell's integers
            # makes the -gt below error out and the clamp fail open.
            ?|??|???) val=$cur ;;
            *) : ;;
          esac
          if [ -n "$val" ] && [ "$val" -gt 255 ]; then val=255; fi

          if [ -n "$val" ]; then
            for b in /sys/class/leds/valve-leds*/brightness; do
              printf '%s' "$val" > "$b" 2>/dev/null || true
            done
            prev=$cur
          fi
        fi
      fi
      sleep 0.2
    done
  '';
in
{
  options = {
    jovian.devices.steammachine = {
      enableLedControl = mkOption {
        default = cfg.enable;
        defaultText = lib.literalExpression "config.jovian.devices.steammachine.enable";
        type = types.bool;
        description = ''
          Whether to loosen access to the Valve LED sysfs attributes.
        '';
      };

      ledUser = mkOption {
        default =
          if options.jovian.steam.user.isDefined
          then config.jovian.steam.user
          else null;
        defaultText = lib.literalExpression "config.jovian.steam.user";
        type = types.nullOr types.str;
        description = ''
          The user granted write access to the Valve LED sysfs attributes.

          Defaults to the user the Steam session runs as, which is only defined
          when {option}`jovian.steam.autoStart` is enabled. When null, no
          permissions are changed and the session cannot drive the LEDs.
        '';
      };

      enableLedBrightnessScale = mkOption {
        default = cfg.enable;
        defaultText = lib.literalExpression "config.jovian.devices.steammachine.enable";
        type = types.bool;
        description = ''
          Whether to mirror Steam's LED brightness slider onto per-LED brightness.

          The slider writes brightness_scale, which has no effect on this
          hardware, so it is applied to each LED's brightness instead.
        '';
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.enableLedControl && cfg.ledUser != null) {
      services.udev.extraRules = ''
        ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="valve-leds*", RUN+="${ledPerms} ${cfg.ledUser} /sys/%p"
      '';
    })

    (mkIf cfg.enableLedBrightnessScale {
      systemd.services.valve-leds-brightness-mirror = {
        description = "Mirror Steam's LED brightness slider onto per-LED brightness";
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = "/sys/devices/platform/valve-leds";
        path = [ pkgs.coreutils ];
        serviceConfig = {
          Type = "simple";
          ExecStart = brightnessMirror;
          Restart = "always";
          RestartSec = 5;
        };
      };
    })
  ];
}
