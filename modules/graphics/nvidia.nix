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

      # The nvidia module only registers EGL/Vulkan display ICDs through
      # hardware.graphics.extraPackages, and this nixpkgs revision has no
      # hardware.nvidia.opencl option at all. The OpenCL ICD manifest is built
      # into the driver's /etc instead, where ocl-icd looks for it, so
      # compute-only consumers such as hashcat would enumerate zero devices
      # without this link.
      environment.etc."OpenCL/vendors/nvidia.icd".source =
        "${config.hardware.nvidia.package}/etc/OpenCL/vendors/nvidia.icd";

      services.xserver.videoDrivers = lib.mkForce [ "nvidia" ];

      boot.blacklistedKernelModules = [ "nouveau" ];

    };
}
