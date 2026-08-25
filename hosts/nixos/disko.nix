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
              size = "36G";
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
                  # The workstation root is multi-terabyte; one percent is
                  # ample root-only recovery space without hiding tens of
                  # gigabytes from normal workloads.
                  "-m"
                  "1"
                ];
              };
            };
          };
        };
      };
      secondary_steam = {
        type = "disk";
        device = "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            steam = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/steam";
                mountOptions = [
                  "defaults"
                  "nofail"
                  "exec"
                  "rw"
                ];
              };
            };
          };
        };
      };
    };
  };
}
