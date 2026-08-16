# Steam Machine-specific configurations
#
# jovian.devices.steammachine

{ config, lib, ... }:

let
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    types
  ;
  cfg = config.jovian.devices.steammachine;
in
{
  imports = [
    ./kernel.nix
    ./leds.nix
  ];

  options = {
    jovian.devices.steammachine = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable Steam Machine-specific configurations.
        '';
      };
    };
  };
  config = mkIf cfg.enable {
    jovian.hardware.has = {
      amd.gpu = true;
    };

    # SteamOS ships no kms hook and no MODULES=(amdgpu), so amdgpu is loaded from
    # udev, after cros_ec_cec has registered its named "Port C" notifier, and
    # amdgpu's unnamed lookup adopts it. Loading amdgpu from the initrd inverts
    # that order: cec_notifier_get_conn() cannot match a named lookup against an
    # unnamed notifier, so the CEC adapter is left on an orphaned notifier, never
    # receives an EDID event, and stays at physical address f.f.f.f.
    #
    # mkDefault so that explicitly setting the option still wins.
    jovian.hardware.amd.gpu.enableEarlyModesetting = mkDefault false;
  };
}
