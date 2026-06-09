{
  pkgs,
  inputs,
  ...
}:
{

  #################################
  # Hyprland (Upstream Flake)
  #################################

  programs.hyprland = {
    enable = true;
    # set the flake package
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    # make sure to also set the portal package, so that they are in sync
    portalPackage =
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;

    withUWSM = true;
    xwayland.enable = true;
  };

  #################################
  # Login Manager (Disabled)
  #################################

  services.greetd.enable = true;
  programs.regreet.enable = true;

  #################################
  # Lock + Idle
  #################################

  programs.hyprlock.enable = true;
  services.hypridle.enable = true;

  #################################
  # Packages
  #################################

  environment.systemPackages = with pkgs; [
    eww
    gtk-layer-shell
    hyprpaper
    hyprsunset
    waypaper
    hyprsysteminfo
  ];
}
