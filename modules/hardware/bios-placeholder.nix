{
  nixos.modules.hardware-bios-placeholder =
    { lib, ... }:
    {
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos-root";
        fsType = "ext4";
      };

      boot.loader.grub.devices = [ "/dev/sda" ];
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    };
}
