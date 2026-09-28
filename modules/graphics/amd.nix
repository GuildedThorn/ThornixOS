{
  nixos.modules.graphics-amd =
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

      # hardware.amdgpu.opencl.enable only pushes rocmPackages.clr.icd onto
      # the system profile, and a system-package install does not symlink its
      # etc/ tree into /etc. ocl-icd only scans /etc/OpenCL/vendors, so without
      # this link the RX 6700 XT is present and healthy but hashcat enumerates
      # zero AMD devices. Same shape as the nvidia.icd link in
      # modules/graphics/nvidia.nix.
      environment.etc."OpenCL/vendors/amdocl64.icd".source =
        "${pkgs.rocmPackages.clr.icd}/etc/OpenCL/vendors/amdocl64.icd";

      hardware.amdgpu.initrd.enable = true;
      services.lact.enable = true;
    };
}
