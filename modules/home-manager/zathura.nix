{
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.zathura;
    in
    {
      options.thorn.programs.zathura.enable =
        lib.mkEnableOption "Thorn's Zathura document viewer configuration";

      config = lib.mkIf cfg.enable {
        programs.zathura = {
          enable = true;
          options = {
            adjust-open = "best-fit";
            database = "sqlite";
            page-padding = 4;
            scroll-page-aware = true;
            selection-clipboard = "clipboard";
            statusbar-home-tilde = true;
            window-title-basename = true;
          };
        };

        programs.yazi.settings = {
          opener.zathura = [
            {
              run = "${lib.getExe config.programs.zathura.package} %s";
              desc = "Zathura";
              for = "linux";
              orphan = true;
            }
          ];
          open.prepend_rules = [
            {
              mime = "application/pdf";
              use = "zathura";
            }
          ];
        };

        xdg.mimeApps = {
          enable = true;
          defaultApplications."application/pdf" = [ "org.pwmt.zathura.desktop" ];
        };
      };
    };
}
