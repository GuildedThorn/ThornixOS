{ ... }:
{
  networking = {
    hostName = "granite";
    # Preserve the existing ZFS host identity; changing it can prevent a
    # clean import of the existing pool after reboot.
    hostId = "708ee474";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.enp3s0.ipv4.addresses = [
      {
        address = "172.16.25.4";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.66"
      "172.16.25.2"
      "172.16.25.1"
    ];
  };
}
