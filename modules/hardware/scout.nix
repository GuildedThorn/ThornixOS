{
  nixos.modules.hardware-scout =
    {
      config,
      lib,
      modulesPath,
      ...
    }:
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      boot.initrd.availableKernelModules = [
        "xhci_pci"
        "nvme"
        "usb_storage"
        "sd_mod"
        "rtsx_pci_sdmmc"
      ];
      boot.kernelModules = [ "kvm-intel" ];

      fileSystems."/" = {
        device = "/dev/mapper/luks-94a756e8-bc39-41e6-b551-94e13bbb4b41";
        fsType = "ext4";
      };
      boot.initrd.luks.devices."luks-94a756e8-bc39-41e6-b551-94e13bbb4b41".device =
        "/dev/disk/by-uuid/94a756e8-bc39-41e6-b551-94e13bbb4b41";
      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/3515-60CB";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };
      swapDevices = [
        { device = "/dev/mapper/luks-2ac28b44-af07-4e07-9ff5-670b09995058"; }
        {
          device = "/var/lib/swapfile";
          size = 32 * 1024;
        }
      ];

      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    };
}
