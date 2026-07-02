{
  nixos.modules."desktop-xfce-i3" =
    { config, pkgs, ... }:

    {

      services.xserver = {
        enable = true;

        desktopManager = {
          xterm.enable = false;
          xfce = {
            enable = true;
            noDesktop = true;
            enableXfwm = false;
          };
        };

        windowManager.i3 = {
          enable = true;
          extraPackages = with pkgs; [
            rofi # application launcher most people use
            i3status # gives you the default i3 status bar
            i3blocks # if you are planning on using i3blocks over i3status
          ];
        };
      };

      environment.pathsToLink = [ "/libexec" ];

      services.displayManager.defaultSession = "xfce+i3";

      programs.dconf.enable = true;
      programs.i3lock.enable = true;

      environment.systemPackages = with pkgs; [
        lxappearance
      ];
    };
}
