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
            # One percent still reserves almost 2 GiB for root recovery on
            # Forge. The ext4 default otherwise hides roughly 9 GiB from a
            # VM whose Nix store is intentionally large.
            extraArgs = [
              "-m"
              "1"
            ];
          };
        };
      };
    };
  };
}
