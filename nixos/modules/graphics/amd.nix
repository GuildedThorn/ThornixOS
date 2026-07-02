{
  nixos.modules."graphics-amd" =
    { pkgs, ... }:
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

      hardware.amdgpu.overdrive = {
        enable = true;
        # Note: Requires ppfeaturemask to be set in kernelParams as shown above
      };

      services.xserver.videoDrivers = [ "amdgpu" ];

      hardware.amdgpu.opencl.enable = true;

      hardware.amdgpu.initrd.enable = true;
      services.lact.enable = true;
    };
}
