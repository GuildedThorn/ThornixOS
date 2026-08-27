{ config, ... }:
{
  nixos.modules.hardware-proxmox-guest =
    { ... }:
    {
      imports = [ config.nixos.modules.hardware-qemu-guest ];

      fileSystems."/" = {
        device = "/dev/sda1";
        autoResize = true;
        fsType = "ext4";
      };
      swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];
    };
}
