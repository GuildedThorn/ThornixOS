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
      "172.16.25.66"
      "172.16.25.2"
      "172.16.25.1"
    ];

    firewall = {
      # Loki and Prometheus are behind nginx mTLS, but reject out-of-scope
      # sources before TLS as a second boundary. 192.168.1.6 is the main
      # workstation on LAN; 10.10.10.4 is scout's WireGuard address; the
      # fixed and DHCP server fleet lives on OPT1.
      extraCommands = ''
        iptables -w -A nixos-fw -p tcp -m multiport --dports 22,3000 -s 172.16.25.3/32 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -m multiport --dports 22,3000 -s 192.168.1.6/32 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -m multiport --dports 22,3000 -s 10.10.10.4/32 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp --dport 3000 -s 172.16.25.51/32 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.0/24 \
          -m multiport --dports 3100,9090 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 \
          -m multiport --dports 3100,9090 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 10.10.10.4/32 \
          -m multiport --dports 3100,9090 -j nixos-fw-accept
        # Purpose-built, read-only news/SIEM correlation and operator-summary
        # APIs. Home Assistant consumes only the bounded operator summary for
        # Deck Voice; Loom uses both routes. nginx independently repeats this
        # source ACL.
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 \
          --dport 9443 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.62/32 \
          --dport 9443 -j nixos-fw-accept
        iptables -w -A nixos-fw -p udp -s 172.16.25.1/32 \
          --dport 5514 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.31/32 \
          --dport 5514 -j nixos-fw-accept
      '';
    };
  };
}
