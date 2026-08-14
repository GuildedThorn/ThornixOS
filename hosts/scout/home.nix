{
  config,
  lib,
  ...
}:
{
  config = lib.mkMerge [
    {
      home.stateVersion = "26.11";
      thorn.desktop.hyprland.enable = true;
      thorn.desktop.rice.enable = true;
      thorn.desktop.wallpaper.enable = true;
      thorn.programs.vesktop.enable = true;
      thorn.programs.firefox.enable = true;
      thorn.programs.ghostty.enable = true;
      thorn.programs.obsidian.enable = true;
      thorn.programs.claude-code.enable = true;
    }
    (lib.mkIf config.thorn.desktop.hyprland.enable {
      wayland.windowManager.hyprland.settings.monitor = [
        {
          output = "eDP-1";
          mode = "highres";
          position = "auto-down";
          scale = "1";
        }
        {
          output = "HDMI-A-2";
          mode = "highres";
          position = "auto-up";
          scale = "auto";
        }
      ];

      # HyprPanel is archived and the shared desktop now runs Wayle. A
      # wildcard layout follows the ThinkPad between its panel and docks.
      services.wayle.settings.bar.layout = [
        {
          monitor = "*";
          show = true;
          left = [
            "dashboard"
            "hyprland-workspaces"
            {
              name = "system";
              modules = [
                "cpu"
                "ram"
                "storage"
              ];
            }
          ];
          center = [
            {
              name = "now-playing";
              modules = [
                "window-title"
                "media"
              ];
            }
          ];
          right = [
            {
              name = "controls";
              modules = [
                "volume"
                "battery"
                "network"
                "bluetooth"
              ];
            }
            "systray"
            {
              module = "clock";
              class = "primary-clock";
            }
            "notifications"
          ];
        }
      ];
    })
  ];
}
