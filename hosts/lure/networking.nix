{ ... }:
{
  networking = {
    hostName = "lure";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.58";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # Lure is intentionally reachable on decoy protocols from ThornCloud's
    # internal networks, never from WAN. Real key-only SSH is a separate
    # recovery plane admitted only from mac, nixos, and Scout's VPN address.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp --dport 22 -s 172.16.25.3/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 22 -s 192.168.1.6/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 22 -s 10.10.10.4/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 9101 -s 172.16.25.51/32 -j nixos-fw-accept

      iptables -w -A nixos-fw -p tcp -m multiport --dports 21,23,80,443,1433,2222,3306,3389,5900,6379,8080,9418,27017 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 21,23,80,443,1433,2222,3306,3389,5900,6379,8080,9418,27017 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 21,23,80,443,1433,2222,3306,3389,5900,6379,8080,9418,27017 -s 10.10.10.0/24 -j nixos-fw-accept

      iptables -w -A nixos-fw -p udp -m multiport --dports 69,123,5060 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p udp -m multiport --dports 69,123,5060 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p udp -m multiport --dports 69,123,5060 -s 10.10.10.0/24 -j nixos-fw-accept
    '';
  };
}
