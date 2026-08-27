{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/wwn-0x500a075112236e91";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        swap = {
          size = "32G";
          content = {
            type = "swap";
            resumeDevice = false;
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
            extraArgs = [
              "-L"
              "nixos-root"
            ];
          };
        };
      };
    };
  };
}
