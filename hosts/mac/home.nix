{
  config,
  lib,
  ...
}:
{
  config = lib.mkMerge [
    {
      home.stateVersion = "26.11";
      thorn.desktop.xfceI3.enable = true;
      thorn.desktop.rice.enable = true;
      thorn.programs.firefox.enable = true;
      thorn.programs.ghostty.enable = true;
      thorn.programs.loom-client.enable = true;
    }
  ];
}
