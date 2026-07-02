{
  nixos.modules.graphics-nvidia =
    { config, lib, ... }:
    {

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
      hardware.nvidia.modesetting.enable = true;
      hardware.nvidia.powerManagement.enable = false;
      hardware.nvidia.powerManagement.finegrained = false;
      hardware.nvidia.open = false;
      hardware.nvidia.nvidiaSettings = true;

      services.xserver.videoDrivers = lib.mkForce [ "nvidia" ];

      boot.blacklistedKernelModules = [ "nouveau" ];

    };
}
