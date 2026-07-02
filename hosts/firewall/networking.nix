{ ... }:
{
  networking = {
    hostName = "firewall";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [ "1.1.1.1" ];

    firewall.allowedTCPPorts = [
      22
    ];
    firewall.allowedUDPPorts = [
      22
    ];
  };

  networking.networkmanager.enable = false;
}
