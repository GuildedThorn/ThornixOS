{ ... }:
{
  # SMART reports drive failures and ZFS Event Daemon reports pool, vdev, and
  # checksum events. The SOC receives both through the enrolled journal stream.
  services.smartd = {
    enable = true;
    autodetect = true;
  };

}
