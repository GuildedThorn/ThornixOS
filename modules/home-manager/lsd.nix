{
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.lsd;
    in
    {
      options.thorn.programs.lsd.enable = lib.mkEnableOption "Thorn's lsd module";

      config = lib.mkIf cfg.enable {
        programs.lsd = {
          enable = true;
        };
      };
    };
}
