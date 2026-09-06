{
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.zellij;
    in
    {
      options.thorn.programs.zellij.enable = lib.mkEnableOption "Thorn's Zellij";

      config = lib.mkIf cfg.enable {
        programs.zellij = {
          enable = true;
          enableZshIntegration = true;

          layouts = {
            default = {
              layout = {
                _children = [
                  {
                    pane = {
                      _props = {
                        size = 1;
                        borderless = true;
                      };

                      _children = [
                        {
                          plugin = {
                            _props = {
                              location = "zellij:tab-bar";
                            };
                          };
                        }
                      ];
                    };
                  }
                ];
              };
            };
          };
        };
      };
    };
}
