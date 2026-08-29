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
    # pfSense resolves the internal .arpa names; 172.16.25.2 was the mitm
    # box, not a DNS server.
    nameservers = [
      "172.16.25.1"
      "1.1.1.1"
    ];

    # Kept as a belt-and-suspenders pin: the SeaweedFS S3 cert is issued
    # for the hostname, so this name must resolve even if pfSense DNS is
    # briefly down.
    hosts = {
      "172.16.25.4" = [ "truenas.guildedthorn.arpa" ];
    };

    # cloudflared is outbound-only. SSH is restricted to administrator hosts,
    # and Owncast ingest is restricted to OBS-capable workstations.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp --dport 22 -s 172.16.25.3/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 22 -s 192.168.1.6/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 22 -s 10.10.10.4/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 1935 -s 192.168.1.6/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 1935 -s 192.168.1.74/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 1935 -s 10.10.10.4/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 8090 -s 172.16.25.51/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 8090 -s 172.16.25.63/32 -j nixos-fw-accept
    '';

  };
}
