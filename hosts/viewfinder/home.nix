{ pkgs, ... }:
{
  home = {
    stateVersion = "26.11";
  };

  thorn.desktop.hyprland.enable = true;
  thorn.programs.ghostty.enable = true;
  thorn.programs.firefox.enable = true;
  thorn.programs.claude-code.enable = true;
}
