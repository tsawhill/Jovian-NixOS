{ config, lib, pkgs, ... }:

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
  options = {
    jovian.devices.steammachine = {
      enableVendorKernel = mkOption {
        type = types.bool;
        default = cfg.enable;
        defaultText = lib.literalExpression "config.jovian.devices.steammachine.enable";
        description = ''
          Whether to use Valve's kernel.

          The CEC controller behind the embedded controller is only driven by
          the vendor tree.
        '';
      };
    };
  };
  config = mkIf (cfg.enableVendorKernel) {
    # Deliberately no fbcon=rotate:1: that is for the Steam Deck's portrait
    # panel and would rotate the console on a landscape display.
    boot.kernelPackages = mkDefault pkgs.linuxPackages_jovian;
  };
}
