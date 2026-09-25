{
  # This is the only disk disko may modify. The ZFS data pool is deliberately
  # absent from this file and must never be added here.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/ata-SanDisk_SDSSDA120G_172450461108";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        swap = {
          size = "8G";
          content = {
            type = "swap";
            resumeDevice = true;
            extraArgs = [ "-L" "swap" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            extraArgs = [ "-L" "granite-root" "-m" "1" ];
          };
        };
      };
    };
  };
}
