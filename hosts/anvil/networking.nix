{ ... }:
{
  networking = {
    hostName = "anvil";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.55";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # Recovery SSH is limited to the three administrator endpoints. The CA API
    # remains available to internal clients, and observability is SOC-only.
    firewall.allowedTCPPorts = [ ];
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp --dport 22 -s 172.16.25.3/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 22 -s 192.168.1.6/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 22 -s 10.10.10.4/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 443 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 443 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 443 -s 10.10.10.0/24 -j nixos-fw-accept
    '';
  };
}
