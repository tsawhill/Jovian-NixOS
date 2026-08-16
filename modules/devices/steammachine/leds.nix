{ config, lib, options, pkgs, ... }:

let
  inherit (lib)
    mkIf
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
    };
  };

  config = mkIf (cfg.enableLedControl && cfg.ledUser != null) {
    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="leds", KERNEL=="valve-leds*", RUN+="${ledPerms} ${cfg.ledUser} /sys/%p"
    '';
  };
}
