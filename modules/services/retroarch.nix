{
  nixos.modules.services-retroarch =
    { pkgs, ... }:

    {

      environment.systemPackages = with pkgs; [
        retroarch
        libretro.pcsx-rearmed
        libretro.pcsx2
      ];
      environment.etc."retroarch/cores".source = pkgs.buildEnv {
        name = "libretro-cores";
        paths = with pkgs.libretro; [
          pcsx2
          pcsx-rearmed
          genesis-plus-gx
          snes9x
        ];
        pathsToLink = [ "/lib/retroarch/cores" ];
      };

      # Tell RetroArch to look there for cores
      environment.etc."retroarch/retroarch.cfg".text = ''
        core_directory = "/etc/retroarch/cores"
        libretro_directory = "/etc/retroarch/cores"
      '';

    };
}
