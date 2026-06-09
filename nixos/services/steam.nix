{
  config,
  lib,
  pkgs,
  ...
}:

{

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  hardware.steam-hardware.enable = true;

  programs.gamemode.enable = true;
  programs.gamescope.capSysNice = true;
  programs.gamescope.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud
  ];
}
