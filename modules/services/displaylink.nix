{
  nixos.modules.services-displaylink =
    { config, pkgs, ... }:
    let
      evdi = config.boot.kernelPackages.evdi;
      # Build the daemon against the same evdi we ship as a kernel module, so
      # the userspace lib matches the loaded module on the running kernel.
      displaylink = pkgs.displaylink.override { inherit evdi; };
    in
    {

      # Enable if using wayland
      # nix-prefetch-url --name displaylink-620.zip https://www.synaptics.com/sites/default/files/exe_files/2025-09/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.2-EXE.zip
      boot.extraModulePackages = [
        evdi
      ];

      # Load evdi at boot so the virtual DRM device exists; the udev hotplug
      # rule only starts the daemon, it does not load the module.
      boot.kernelModules = [
        "evdi"
      ];

      # 99-displaylink.rules tags the dock and asks systemd to start
      # dlm.service when it is plugged in. Without it the device is enumerated
      # over USB but never driven.
      services.udev.packages = [
        displaylink
      ];

      systemd.services.dlm = {
        enable = true;
        description = "DisplayLink Manager Service";
        after = [ "systemd-udevd.service" ];
        requires = [ "systemd-udevd.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${displaylink}/bin/DisplayLinkManager";
          Restart = "on-failure";
          RestartSec = 5;
          User = "root";
          Group = "root";
          LogsDirectory = "displaylink";
        };
      };

      # Enable if using X11
      # services.xserver.videoDrivers = [ "displaylink" "modesetting" ];

    };
}
