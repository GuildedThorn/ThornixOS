{ pkgs, ... }:
{
  home = {
    stateVersion = "26.11";
  };

  thorn.desktop.hyprland.enable = true;
  thorn.desktop.rice.enable = true;
  thorn.programs.vesktop.enable = true;
  thorn.programs.ghostty.enable = true;
  thorn.programs.firefox.enable = true;
  thorn.programs.claude-code.enable = true;

  wayland.windowManager.hyprland.settings.monitor = [
    {
      output = "DP-1";
      mode = "4096x2160@29.97";
      position = "10241x4775";
      scale = "1.0";
    }
    {
      output = "HDMI-A-1";
      mode = "1920x1080@60.0";
      position = "8321x5855";
      scale = "1.0";
    }
    {
      output = "DP-2";
      mode = "1280x768@59.99";
      position = "8321x6935";
      scale = "2.0";
    }
  ];
}
