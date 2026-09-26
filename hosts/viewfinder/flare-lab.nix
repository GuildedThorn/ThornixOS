{
  # Live configuration of the detonation lab VMs on this node, as of the
  # `pre-agent-enable` snapshot on VM 200. Keyed by vmid.
  #
  # Both are on vmbr1, which has no uplink and no gateway, so nothing here can
  # reach the internet even if a sample tries. Both also have Proxmox's
  # firewall enabled on the NIC, which is asserted nowhere and so is only
  # recorded here for whoever reconciles the firewall rules.
  nixos.modules.services-flare-lab = {
    # Enabled here rather than in the module list because the inventory below
    # is the whole reason to turn it on: there is nothing to check otherwise.
    enable = true;

    inventory = {
      "200" = {
        description = "Windows detonation guest";
        name = "flare-vm";
        bridge = "vmbr1";
        macAddress = "BC:24:11:71:28:B1";
        memoryMiB = 4096;
        cores = 4;
        guestAgent = true;
        # Deliberately off: the lab should come up only when someone intends to
        # use it, and a booting detonation guest is a standing source of noise
        # for the Zeek sensor on this same host.
        onboot = false;
      };

      "201" = {
        description = "REMnux analysis host, INetSim sinkhole";
        name = "remnux";
        bridge = "vmbr1";
        macAddress = "BC:24:11:03:AD:56";
        memoryMiB = 4096;
        cores = 4;
        guestAgent = true;
        onboot = false;
      };
    };
  };
}
