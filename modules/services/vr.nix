{
  nixos.modules.services-vr =
    { pkgs, ... }:

    {

      services.monado = {
        enable = false;
        defaultRuntime = false;
        highPriority = true;
      };

      boot.kernelPatches = [
        {
          name = "amdgpu-ignore-ctx-privileges";
          patch = pkgs.fetchpatch {
            name = "cap_sys_nice_begone.patch";
            url = "https://github.com/Frogging-Family/community-patches/raw/master/linux61-tkg/cap_sys_nice_begone.mypatch";
            hash = "sha256-Y3a0+x2xvHsfLax/uwycdJf3xLxvVfkfDVqjkxNaYEo=";
          };
        }
      ];

      programs.steam.package = pkgs.steam.override {
        extraProfile = ''
          # Fix VRChat timezone bug
          unset TZ

          # Steam's CEF hover menus render incorrectly when forced onto
          # Wayland by the global NIXOS_OZONE_WL setting.
          unset NIXOS_OZONE_WL

          # Allow custom OpenXR runtimes (WiVRn / Monado)
          export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
        '';
      };

      services.wivrn = {
        enable = true;
        openFirewall = true;

        autoStart = true;
      };

      environment.sessionVariables = {
        NIXOS_OZONE_WL = "1";
      };

    };
}
