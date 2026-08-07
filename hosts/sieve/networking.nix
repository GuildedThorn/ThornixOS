{ ... }:
{
  networking = {
    hostName = "sieve";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.56";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # Greenbone's published container port is loopback-only. The NixOS nginx
    # listener and key-only recovery SSH are the only externally reachable
    # services; node/comin metrics are separately admitted only from SOC.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 10.10.10.0/24 -j nixos-fw-accept
    '';
  };
}
