{ ... }:
{
  networking = {
    hostName = "hound";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.57";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # The GUI, client frontend, and key-only SSH stay on ThornCloud's trusted
    # networks. Velociraptor's native metrics listener is independently
    # restricted to the SOC host.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443,8000 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443,8000 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443,8000 -s 10.10.10.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 8003 -s 172.16.25.51/32 -j nixos-fw-accept
    '';
  };
}
