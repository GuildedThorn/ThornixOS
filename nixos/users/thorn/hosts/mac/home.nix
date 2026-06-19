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
      thorn.programs.firefox.enable = true;
      thorn.programs.ghostty.enable = true;
    }
  ];
}
