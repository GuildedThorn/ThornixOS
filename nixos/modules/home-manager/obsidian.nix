{
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.obsidian;
    in
    {
      options.thorn.programs.obsidian.enable =
        lib.mkEnableOption "Thorn's Obsidian Home Manager configuration";

      config = lib.mkIf cfg.enable {
        programs.obsidian.enable = true;
      };
    };
}
