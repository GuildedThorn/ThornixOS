{ ... }:
{

  home.stateVersion = "26.05";

  wayland.windowManager.hyprland.settings.monitor = [
    "desc:Chrontel Inc TV DISPLAY,720x480@60.0,4887x3610,0.670000"
    "desc:LG Electronics 24GN50W 0x0006C019,1920x1080@144.0,489x3250,1.0"
    "desc:HP Inc. HP X24ih 1CR1211S3F,1920x1080@143.98,2409x3250,1.0"
  ];

  programs.hyprpanel.settings.bar.layouts = {
    "DP-2" = {
      left = [
        "dashboard"
        "workspaces"
        "clock"
      ];
      middle = [ "windowtitle" ];
      right = [
        "network"
        "systray"
      ];
    };
    "DP-3" = {
      left = [
        "cpu"
        "cputemp"
        "ram"
        "storage"

      ];
      middle = [
        "media"
        "cava"
      ];
      right = [
        "volume"
        "bluetooth"
        "notifications"
      ];
    };
  };

}
