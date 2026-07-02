{
  nixos.modules.services-vmware-guest =
    { ... }:

    {

      # Used for nixos systems inside vmware
      virtualisation.vmware.guest.enable = true;

    };
}
