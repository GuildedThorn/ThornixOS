{ ... }:
{
  networking = {
    hostName = "resolver";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.66";
        prefixLength = 24;
      }
    ];
    defaultGateway = "172.16.25.1";
    nameservers = [ "172.16.25.1" ];

    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p udp -s 172.16.25.0/24 --dport 53 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 172.16.25.0/24 --dport 53 -j nixos-fw-accept
      iptables -w -A nixos-fw -p udp -s 192.168.1.0/24 --dport 53 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 192.168.1.0/24 --dport 53 -j nixos-fw-accept
      iptables -w -A nixos-fw -p udp -s 10.10.10.0/24 --dport 53 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 10.10.10.0/24 --dport 53 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 172.16.25.0/24 --dport 443 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 192.168.1.0/24 --dport 443 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 10.10.10.0/24 --dport 443 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 53443 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 172.16.25.3/32 --dport 22 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 --dport 22 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -s 10.10.10.4/32 --dport 22 -j nixos-fw-accept
    '';
  };
}
