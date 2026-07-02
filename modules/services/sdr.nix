{
  nixos.modules.services-sdr =
    {
      pkgs,
      ...
    }:

    {

      environment.systemPackages = [
        pkgs.hackrf
      ];

      hardware.rtl-sdr.enable = true;

      hardware.hackrf.enable = true;

    };
}
