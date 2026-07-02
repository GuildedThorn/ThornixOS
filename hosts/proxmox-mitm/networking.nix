{ ... }:
{

  networking = {
    hostName = "proxmox-mitm";
    enableIPv6 = false;
    useDHCP = false;

    nameservers = [ "8.8.8.8" ];

    interfaces.ens18 = {
      ipv4.addresses = [
        {
          address = "172.16.100.2";
          prefixLength = 24;
        }
      ];
    };

    firewall.allowedTCPPorts = [
      22
      53
      67
      68
      5380
    ];

    firewall.allowedUDPPorts = [
      22
      53
      67
      68
      5380
    ];
  };

}
