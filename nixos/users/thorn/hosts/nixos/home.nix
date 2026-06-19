{
  config,
  inputs,
  lib,
  ...
}:
{
  config = lib.mkMerge [
    {
      home.stateVersion = "26.05";
      thorn.desktop.hyprland.enable = true;
      thorn.desktop.rice.enable = true;
      thorn.programs.vesktop.enable = true;
      thorn.programs.firefox.enable = true;
      thorn.programs.ghostty.enable = true;
      thorn.programs.obsidian.enable = true;
    }
    (lib.mkIf config.thorn.desktop.hyprland.enable {
      wayland.windowManager.hyprland.settings.monitor = [
        {
          output = "desc:Chrontel Inc TV DISPLAY";
          mode = "720x480@60.0";
          position = "4887x3610";
          scale = "0.670000";
        }
        {
          output = "desc:LG Electronics 24GN50W 0x0006C019";
          mode = "1920x1080@144.0";
          position = "489x3250";
          scale = "1.0";
        }
        {
          output = "desc:HP Inc. HP X24ih 1CR1211S3F";
          mode = "1920x1080@143.98";
          position = "2409x3250";
          scale = "1.0";
        }
      ];

      services.wayle.settings = {
        inset-edge = 0.5;
        inset-ends = 0.5;
        layout = [
          {
            center = [
              "cava"
              "media"
            ];
            left = [
              "dashboard"
              "weather"
              "separator"
              "hyprland-workspaces"
              "separator"
              "clock"
              "world-clock"
            ];
            monitor = "DP-2";
            right = [
              "network"
              "netstat"
              "separator"
              "systray"
            ];
            show = true;
          }
          {
            center = [ "window-title" ];
            left = [
              "hyprland-workspaces"
              "separator"
              "cpu"
              "ram"
              "storage"
            ];
            monitor = "DP-3";
            right = [
              "volume"
              "hyprsunset"
              "bluetooth"
              "notifications"
            ];
            show = true;
          }
        ];
      };
    })
  ];
}
