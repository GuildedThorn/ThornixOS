{
  nixos.modules.hardware-mitm =
    { config, lib, ... }:
    {
      boot.initrd.availableKernelModules = [
        "ahci"
        "nvme"
        "sd_mod"
        "sr_mod"
        "xhci_pci"
      ];
      boot.kernelModules = [ "kvm-intel" ];

      hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    };
}
