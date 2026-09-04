{
  nixos.modules.services-bluetooth =
    { lib, pkgs, ... }:
    {

      # Enable bluetooth with blueman
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        input.General.ClassicBondedOnly = false;
        settings = {
          General = {
            AutoEnable = true;
            FastConnectable = true;
            Experimental = true;
            JustWorksRepairing = "always";
            Privacy = "device";
          };
        };
        package = pkgs.bluez;
      };

      services.blueman.enable = lib.mkDefault true;

      # Enable game controller support
      hardware.uinput.enable = true;

      # DualShock 4 kernel driver
      boot.kernelModules = [
        "hid-sony"
        "hid-sony-ps"
        "hid-playstation"
      ];
    };
}
