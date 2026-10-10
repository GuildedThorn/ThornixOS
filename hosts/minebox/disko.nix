{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/ata-SK_hynix_SC401_SATA_256GB_MI95N002911005351";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        swap = {
          size = "8G";
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
