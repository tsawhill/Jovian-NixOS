{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkIf
    mkOption
    types
    ;
  cfg = config.jovian.steamos;
in
{
  options = {
    jovian.steamos = {
      enableHdmiCecIntegration = mkOption {
        default = cfg.useSteamOSConfig;
        defaultText = lib.literalExpression "config.jovian.steamos.useSteamOSConfig";
        type = types.bool;
        description = ''
          Whether to enable SteamOS HDMI-CEC integration.
        '';
      };
    };
  };

  config = mkIf cfg.enableHdmiCecIntegration {
    warnings = lib.optional
      (config.jovian.devices.steammachine.enable
        && config.jovian.hardware.amd.gpu.enableEarlyModesetting) ''
        jovian.hardware.amd.gpu.enableEarlyModesetting is enabled on a Steam Machine
        together with jovian.steamos.enableHdmiCecIntegration.

        Loading amdgpu from the initrd makes it register an unnamed CEC notifier
        before cros-ec-cec can register its named one. cec_notifier_get_conn()
        cannot match a named lookup against an unnamed notifier, so the CEC adapter
        is left on an orphan, never receives an EDID event, and stays at physical
        address f.f.f.f. SteamOS does not enable early modesetting, which is why it
        is unaffected.

        Unset jovian.hardware.amd.gpu.enableEarlyModesetting to restore the Steam
        Machine default of false. This does not affect
        jovian.hardware.amd.gpu.enableBacklightControl.
      '';

    environment.systemPackages = [ pkgs.cecd ];
    services.dbus.packages = [ pkgs.cecd ];
    services.udev.packages = [
      pkgs.cecd
      pkgs.inputattach-cec-units
    ];
    systemd.packages = [
      pkgs.cecd
      pkgs.inputattach-cec-units
    ];

    systemd.user.services.cecd = {
      overrideStrategy = "asDropin";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "steamos-manager-configure-cecd.service" ];
      after = [ "steamos-manager-configure-cecd.service" ];
    };
  };
}
