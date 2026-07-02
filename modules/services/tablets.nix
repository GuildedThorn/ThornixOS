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

      # Enable touchpad support (enabled default in most desktopManager).
      # services.xserver.libinput.enable = true;

    };
}
