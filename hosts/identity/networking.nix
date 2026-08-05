{ ... }:
{
  networking = {
    hostName = "identity";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.52";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # SSH is a key-only recovery path. Authentik itself and its unauthenticated
    # metrics endpoint are admitted below only from their intended networks.
    firewall.allowedTCPPorts = [ 22 ];
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp --dport 443 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 443 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 443 -s 10.10.10.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 9300 -s 172.16.25.51/32 -j nixos-fw-accept
    '';
  };
}
