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

    # The RDNA3 tuning from Valve's grub-steamos, which moved out of the generic
    # SteamOS cmdline into the Deck profile in #602.
    boot.kernelParams = [
      # Valve says:
      # amdgpu.sched_hw_submission is set to 4 to avoid bubbles of lack-of work
      # with the default (2).
      # 4 is the maximum that is supported across RDNA2 + RDNA3.
      # Any more results in a hang at startup on RDNA3.
      "amdgpu.sched_hw_submission=4"

      # DC_DISABLE_SUBVP_FAMS: Sub-Viewport and firmware-assisted MCLK switching
      # exist on this DCN 3.2.1 display engine. The 0x40000 bit Valve also sets
      # only affects a built-in panel's backlight curve, which this has none of.
      "amdgpu.dcdebugmask=0x20000"
    ];
  };
}
