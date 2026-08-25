{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        swap = {
          size = "2G";
          content = {
            type = "swap";
            resumeDevice = true;
            extraArgs = [
              "-L"
              "swap"
            ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            # Two percent is ample emergency headroom on this small,
            # appliance-style root filesystem; ext4's default five percent
            # unnecessarily hides almost a gigabyte from normal services.
            extraArgs = [
              "-m"
              "2"
            ];
          };
        };
      };
    };
  };
}
