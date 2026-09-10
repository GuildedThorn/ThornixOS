{
  # sc0710 ECP5 FPGA runtime firmware for the Elgato 4K Pro (1cfa:0012), not the
  # MK.2 (1cfa:000e — that card is plug-and-play). The 4K Pro's FPGA config is
  # volatile: the driver programs the ECP5 on every module load and aborts the
  # probe if /lib/firmware/sc0710/SC0710.FWI.HEX is missing. The firmware only
  # ships inside Elgato's Windows driver installer, so it's vendored here
  # (vendor/sc0710/SC0710.FWI.HEX, sha256 80558bb8...252) and installed through
  # hardware.firmware so reinstall/rebuild survives.
  nixos.modules.hardware-sc0710-firmware =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      firmware = pkgs.runCommand "sc0710-firmware" { } ''
        mkdir -p $out/lib/firmware/sc0710
        cp ${../..}/vendor/sc0710/SC0710.FWI.HEX $out/lib/firmware/sc0710/
      '';
    in
    {
      # Gated on the upstream sc0710 module's enable flag (declared by
      # inputs.sc0710), so this module also evaluates cleanly on hosts that
      # import-tree pulls in but that never enable sc0710.
      config = lib.mkIf (lib.attrByPath [ "sc0710" "enable" ] false config.hardware) {
        hardware.firmware = [ firmware ];
      };
    };
}
