{ ... }:
{
  networking = {
    hostName = "herald";
    enableIPv6 = false;
    useDHCP = false;

    interfaces.eth0.ipv4.addresses = [
      {
        address = "172.16.25.63";
        prefixLength = 24;
      }
    ];

    defaultGateway = "172.16.25.1";
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # ntfy's HTTP listener and metrics stay on loopback. HTTPS is available
    # to trusted ThornixOS networks; local SMTP-to-topic publishing is limited
    # to OPT1 and still requires a topic access token in the recipient address.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 172.16.25.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 192.168.1.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,443 -s 10.10.10.0/24 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 25 -s 172.16.25.0/24 -j nixos-fw-accept
    '';
  };
}
