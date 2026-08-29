{ ... }:
{
  networking = {
    hostName = "courier";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.64";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # Bootstrap HTTP/8080 is intentionally not opened: reach it through the
    # documented SSH tunnel. After bootstrap, only authenticated mail-client
    # protocols and HTTPS are reachable from trusted internal networks. Port
    # 25 stays closed until public DNS, PTR, NAT, and delivery policy exist.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp --dport 22 -s 172.16.25.3/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 22 -s 192.168.1.6/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 22 -s 10.10.10.4/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 443,465,587,993 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 443,465,587,993 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 443,465,587,993 -s 10.10.10.0/24 -j nixos-fw-accept
    '';
  };
}
