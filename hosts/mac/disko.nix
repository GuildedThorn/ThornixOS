{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {

            ESP = {
              size = "487M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
                extraArgs = [
                  "-n"
                  "ESP"
                ];
              };
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
    };
  };
}
