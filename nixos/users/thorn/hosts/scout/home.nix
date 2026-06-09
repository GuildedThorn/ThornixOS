{
  inputs,
  ...
}:
{

  home.stateVersion = "26.05";

  wayland.windowManager.hyprland.settings.monitor = [
    "eDP-1,1920x1080@60.05,1920x1080,1"
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

  services.hyprpaper.settings.wallpaper = [
    {
      monitor = "eDP-1";
      path = "${inputs.self}/users/thorn/pictures/FullLogo.png";
    }
  ];
}
