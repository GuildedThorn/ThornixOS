{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.desktop.rice;
    in
    {
      options.thorn.desktop.rice.enable =
        lib.mkEnableOption "Thorn's shared desktop rice for Hyprland and xfce+i3";

      config = lib.mkIf cfg.enable {
        programs.rofi = {
          enable = true;
          theme = "fullscreen-preview.rasi";
        };
        stylix.targets.rofi.enable = false;

        gtk.enable = true;

        home.pointerCursor = {
          gtk.enable = true;
          x11.enable = true;
          name = "Bibata-Modern-Ice";
          size = 24;
          package = pkgs.bibata-cursors;
        };
      };
    };
}
