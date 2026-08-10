{ ... }:
{
  networking = {
    hostName = "loom";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.62";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # n8n and PostgreSQL remain on loopback/Unix sockets. Only the nginx TLS
    # edge and key-only SSH are reachable from trusted ThornixOS networks.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 10.10.10.0/24 -j nixos-fw-accept
    '';
  };
}
