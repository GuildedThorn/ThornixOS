{ ... }:
{
  networking = {
    hostName = "pixie";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.53";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # SSH remains the key-only recovery path. HTTP and TFTP are admitted by
    # services-pixie-netboot only from the two trusted internal subnets.
    firewall.allowedTCPPorts = [ 22 ];
  };
}
