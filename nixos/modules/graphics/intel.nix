{
  nixos.modules."graphics-intel" =
    { pkgs, ... }:
    {

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          # your Open GL, Vulkan and VAAPI drivers
          intel-vaapi-driver
          intel-media-driver
          vpl-gpu-rt # for newer GPUs on NixOS >24.05 or unstable
          # onevpl-intel-gpu  # for newer GPUs on NixOS <= 24.05
          # intel-media-sdk   # for older GPUs
        ];
      };

    };
}
