{ pkgs, ... }:

{

  # Used to host vmware workstation
  virtualisation.vmware.host.enable = true;
  virtualisation.vmware.host.package = pkgs.vmware-workstation.override { enableMacOSGuests = true; };
  boot.kernelModules = [
    "vmmon"
    "vmnet"
  ];

  # Used for nixos systems inside vmware
  # virtualisation.vmware.guest.enable = true;
  # virtualisation.docker = {
  # enable = true;
  # enableOnBoot = true;
  # autoPrune.enable = true;
  # extraOptions = ''--iptables=false --ip6tables=false'';
  # };

}
