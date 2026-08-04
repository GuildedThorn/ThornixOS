{ ... }:
{
  networking = {
    hostName = "soc";
    enableIPv6 = false;
    useDHCP = false;

    # Static like websites (.50) — the whole fleet ships logs here, and the
    # pfSense host override for soc.guildedthorn.arpa points at this.
    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.51";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1" # pfSense — resolves .arpa LAN names (truenas S3, scrape targets)
      "1.1.1.1"
    ];

    firewall = {
      allowedTCPPorts = [
        22
        3000 # Grafana
      ];

      # Loki and Prometheus are behind nginx mTLS, but reject out-of-scope
      # sources before TLS as a second boundary. 10.10.10.3 is scout's
      # WireGuard address; the fixed and DHCP fleet live on OPT1.
      extraCommands = ''
        iptables -w -A nixos-fw -p tcp -s 172.16.25.0/24 \
          -m multiport --dports 3100,9090 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 10.10.10.3/32 \
          -m multiport --dports 3100,9090 -j nixos-fw-accept
        iptables -w -A nixos-fw -p udp -s 172.16.25.1/32 \
          --dport 5514 -j nixos-fw-accept
      '';
    };
  };
}
