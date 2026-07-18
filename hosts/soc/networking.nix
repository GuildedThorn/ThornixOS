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

    firewall.allowedTCPPorts = [
      22
      3000 # Grafana
      3100 # Loki push (Alloy on every host)
      9090 # Prometheus remote_write receiver (roaming hosts: scout over WireGuard)
    ];
  };
}
