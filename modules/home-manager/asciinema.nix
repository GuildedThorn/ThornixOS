{
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.asciinema;
    in
    {
      options.thorn.programs.asciinema.enable =
        lib.mkEnableOption "Thorn's asciinema Home Manager configuration";

      config = lib.mkIf cfg.enable {
        programs.asciinema.enable = true;
      };
    };
}
