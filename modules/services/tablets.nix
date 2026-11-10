{
  nixos.modules.services-tablets =
    { ... }:

    {

      hardware.uinput.enable = true;
      boot.kernelModules = [
        "uinput"
      ];

      # Enable drawing tablet support
      hardware.opentabletdriver.enable = true;

    };
}
