{
  nixos.modules.services-displaylink =
    { config, pkgs, ... }:
    {

      # Enable if using wayland
      # nix-prefetch-url --name displaylink-600.zip https://www.synaptics.com/sites/default/files/exe_files/2025-09/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.2-EXE.zip
      boot.extraModulePackages = with config.boot.kernelPackages; [
        evdi
      ];

      systemd.services.displaylink-server = {
        enable = true;
        description = "DisplayLink Manager Service";
        after = [ "systemd-udevd.service" ];
        requires = [ "systemd-udevd.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.displaylink}/bin/DisplayLinkManager";
          Restart = "on-failure";
          RestartSec = 5;
          User = "root";
          Group = "root";
        };
      };

      # Enable if using X11
      # services.xserver.videoDrivers = [ "displaylink" "modesetting" ];

    };
}
