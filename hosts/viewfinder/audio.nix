{
  services.pipewire.extraConfig = {
    context.properties = {
      # 48000Mhz
      default.clock.rate = 48000;

      # Do not allow baud to dynamically cycle to a lower quality
      default.clock.allowed-rates = [ 48000 ];

      default.clock.quantumn = 512;
      default.clock.min-quantumn = 128;
      default.clock.max-quantumn = 2048;
    };
  };

  security.pam.loginLimits = [
    {
      domain = "@audio";
      item = "memlock";
      type = "-";
      value = "unlimited";
    }
    {
      domain = "@audio";
      item = "rtprio";
      type = "-";
      value = "95";
    }
  ];

  # Anti 5 second idle hack for this interface
  # Thanks: https://bbs.archlinux.org/viewtopic.php?id=294949
  wireplumber.extraConfig."51-scarlett-no-suspend" = {
    monitor.alsa.rules = [
      {
        matches = [
          { node.name = "~alsa_output\\.usb-*scarlett_Solo.*"; }
          { node.name = "~alsa_input\\.usb-*scarlett_Solo.*}"; }
        ];
        actions.update-props."session.suspend-timeout-seconds" = 0;
      }
    ];
  };

  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1235", TEST=="power/control", ATTR{power/control}="on"
  '';
}
