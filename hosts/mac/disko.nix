{
  disko.devices = {
    disk = {
      # Second internal bay: Seagate BarraCuda 1 TB HDD. Bulk Proxmox
      # storage only — guest images for idle infrastructure guests, never
      # the system disk. Its WWN/ata id is stable across enumeration
      # changes so Disko cannot select the wrong drive.
      bulk = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST1000DM010-2EP102_Z9ALPKFD";
        content = {
          type = "gpt";
          partitions = {
            bulk = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/pve/bulk";
                extraArgs = [
                  "-L"
                  "bulk"
                  # Pure data disk; one percent still gives root a recovery
                  # margin without hiding capacity from Proxmox.
                  "-m"
                  "1"
                ];
              };
            };
          };
        };
      };

      main = {
        type = "disk";
        # The Mac Pro has one internal system disk. Use its stable WWN rather
        # than /dev/sda so Disko cannot select a different disk if enumeration
        # changes during the nixos-anywhere kexec environment.
        device = "/dev/disk/by-id/wwn-0x5002538f5590522d";
        content = {
          type = "gpt";
          partitions = {

            ESP = {
              size = "1G";
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
                  # The default five-percent reserve is roughly 46 GiB on
                  # this disk. One percent still leaves about 9 GiB for root
                  # recovery while exposing useful capacity to Proxmox.
                  "-m"
                  "1"
                ];
              };
            };
          };
        };
      };
    };
  };
}
