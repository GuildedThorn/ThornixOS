{ ... }:

{
  networking = {
    hostName = "mitm";
    domain = "guildedthorn.arpa";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [
      "172.16.25.1" # pfSense — resolves .arpa LAN names
      "1.1.1.1"
    ];

    firewall.allowedTCPPorts = [ 443 ];

  };

  networking.networkmanager.enable = false;
}
