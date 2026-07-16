{
  homeManager.modules.thorn =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.dorion;
    in
    {
      options.thorn.programs.dorion.enable =
        lib.mkEnableOption "Thorn's Dorion Home Manager configuration";

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.dorion ];
      };
    };
}
