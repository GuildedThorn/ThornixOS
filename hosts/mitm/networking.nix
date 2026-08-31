{ ... }:

{
  networking = {
    hostName = "mitm";
    domain = "guildedthorn.arpa";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [
      "172.16.25.1" # pfSense — resolves .arpa LAN names
      "1.1.1.1"
    ];

    firewall = {
      allowedTCPPorts = [ 443 ];
      # SSH is administrator-only. The Deck may use MITM's fast Piper voice
      # for short acknowledgements.
      extraCommands = ''
        iptables -w -A nixos-fw -p tcp -s 172.16.25.3/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 10.10.10.4/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.26/32 --dport 10200 -j nixos-fw-accept
        iptables -w -A nixos-fw -p udp -s 172.16.25.0/24 --dport 53 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.0/24 --dport 53 -j nixos-fw-accept
        iptables -w -A nixos-fw -p udp -s 192.168.1.0/24 --dport 53 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.0/24 --dport 53 -j nixos-fw-accept
        iptables -w -A nixos-fw -p udp -s 10.10.10.0/24 --dport 53 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 10.10.10.0/24 --dport 53 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.66/32 -m multiport --dports 5380,53443 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.3/32 -m multiport --dports 5380,53443 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 -m multiport --dports 5380,53443 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 10.10.10.4/32 -m multiport --dports 5380,53443 -j nixos-fw-accept
      '';
    };

  };

  networking.networkmanager.enable = false;
}
