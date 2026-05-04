{ pkgs, ... }:

{

  programs.envision = {
    enable = true;
    openFirewall = true; # This is set true by default
  };

  services.monado = {
    enable = false;
    defaultRuntime = false;
    highPriority = true;
  };

  #    systemd.user.services.monado.environment = {
  #        STEAMVR_LH_ENABLE = "1";
  #        XRT_COMPOSITOR_COMPUTE = "1";
  #    };

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

      # Allow custom OpenXR runtimes (WiVRn / Monado)
      export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
    '';
  };

  services.wivrn = {
    enable = true;
    openFirewall = true;

    # Write information to /etc/xdg/openxr/1/active_runtime.json, VR applications
    # will automatically read this and work with WiVRn (Note: This does not currently
    # apply for games run in Valve's Proton)

    # Run WiVRn as a systemd service on startup
    autoStart = true;

    # If you're running this with an nVidia GPU and want to use GPU Encoding (and don't otherwise have CUDA enabled system wide), you need to override the cudaSupport variable.
    #package = (pkgs.wivrn.override { cudaSupport = true; });

    # You should use the default configuration (which is no configuration), as that works the best out of the box.
    # However, if you need to configure something see https://github.com/WiVRn/WiVRn/blob/master/docs/configuration.md for configuration options and https://mynixos.com/nixpkgs/option/services.wivrn.config.json for an example configuration.
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

}
