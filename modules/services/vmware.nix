{
  nixos.modules.services-vmware =
    { pkgs, ... }:

    {

      # Used to host vmware workstation
      virtualisation.vmware.host.enable = true;
      virtualisation.vmware.host.package = pkgs.vmware-workstation.override { enableMacOSGuests = true; };
      boot.kernelModules = [
        "vmmon"
        "vmnet"
      ];

    };
}
