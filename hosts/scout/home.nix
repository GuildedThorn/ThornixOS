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
      thorn.programs.vesktop.enable = true;
      thorn.programs.firefox.enable = true;
      thorn.programs.ghostty.enable = true;
      thorn.programs.obsidian.enable = true;
      thorn.programs.thunderbird.enable = true;
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

      programs.hyprpanel.settings.bar.layouts = {
        "eDP-1" = {
          left = [
            "dashboard"
            "workspaces"
            "separator"
            "cpu"
            "cputemp"
            "ram"
            "storage"
          ];
          middle = [
            "windowtitle"
            "separator"
            "media"
          ];
          right = [
            "volume"
            "battery"
            "network"
            "bluetooth"
            "systray"
            "clock"
            "notifications"
          ];
        };
      };
    })
  ];
}
