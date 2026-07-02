{
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.ghostty;
    in
    {
      options.thorn.programs.ghostty.enable =
        lib.mkEnableOption "Thorn's Ghostty Home Manager configuration";

      config = lib.mkIf cfg.enable {
        programs.ghostty = {
          enable = true;
          systemd.enable = true;
          enableZshIntegration = true;
          installBatSyntax = true;
          installVimSyntax = true;
          settings = {
            font-family = "GeistMono Nerd Font";
            font-style = "Regular";
            font-size = 14;

            adjust-cell-height = "2%";

            cursor-style = "block";

            window-padding-x = 10;
            window-padding-y = 10;

            background-opacity = 0.80;
            copy-on-select = false;

            mouse-hide-while-typing = true;
            shell-integration = "detect";

            link-url = true;

            shell-integration-features = "ssh-env,ssh-terminfo";
          };
        };
      };
    };
}
