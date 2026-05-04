{ config, pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    radeontop
    vulkan-tools

    rocmPackages.rocblas
    rocmPackages.hipblas
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };

  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.amdgpu.opencl.enable = true;

  hardware.amdgpu.initrd.enable = true;
  services.lact.enable = true;
  hardware.amdgpu.overdrive.enable = true;
}
