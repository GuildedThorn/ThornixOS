{ ... }:
{
  networking = {
    hostName = "websites";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.50";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.2"
      "1.1.1.1"
    ];

    # cloudflared is outbound-only; only SSH is exposed publicly.
    firewall.allowedTCPPorts = [
      22
    ];

    firewall.extraCommands = ''
      iptables -A nixos-fw -p tcp --dport 8000 -s 10.0.0.0/8 -j nixos-fw-accept
      iptables -A nixos-fw -p tcp --dport 8000 -s 172.16.0.0/12 -j nixos-fw-accept
      iptables -A nixos-fw -p tcp --dport 8000 -s 192.168.0.0/16 -j nixos-fw-accept
      iptables -A nixos-fw -p tcp --dport 1935 -s 10.0.0.0/8 -j nixos-fw-accept
      iptables -A nixos-fw -p tcp --dport 1935 -s 172.16.0.0/12 -j nixos-fw-accept
      iptables -A nixos-fw -p tcp --dport 1935 -s 192.168.0.0/16 -j nixos-fw-accept
    '';

  };
}
