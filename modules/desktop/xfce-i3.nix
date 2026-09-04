{
  nixos.modules.desktop-xfce-i3 =
    {
      config,
      lib,
      pkgs,
      ...
    }:

    let
      managedSession = config.home-manager.users.thorn.thorn.desktop.xfceI3.enable;
    in
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

      # XFCE enables gnome-keyring by default, which defaults gcr-ssh-agent
      # to enabled too. Thorn's user baseline owns SSH_AUTH_SOCK instead.
      services.gnome.gcr-ssh-agent.enable = false;

      # Dunst is the configured notification daemon for this session.
      environment.xfce.excludePackages = lib.optionals managedSession [ pkgs.xfce4-notifyd ];

      programs.dconf.enable = true;
      programs.i3lock.enable = true;

      environment.systemPackages = with pkgs; [
        lxappearance
      ];
    };
}
