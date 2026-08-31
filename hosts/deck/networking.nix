{
  networking = {
    hostName = "deck";
    domain = "guildedthorn.arpa";
    networkmanager = {
      enable = true;
      settings.main.no-auto-default = "00:e0:4c:68:15:f3";
      ensureProfiles.profiles.deck-ethernet = {
        connection = {
          id = "Deck Ethernet";
          type = "ethernet";
          interface-name = "enp4s0f3u1u1";
          autoconnect = true;
        };
        ethernet.mac-address = "00:e0:4c:68:15:f3";
        ipv4 = {
          method = "manual";
          addresses = "172.16.25.26/24";
          gateway = "172.16.25.1";
          dns = "172.16.25.1;";
          dns-search = "guildedthorn.arpa;";
          route-metric = 100;
        };
        ipv6.method = "disabled";
      };
    };
    firewall = {
      enable = true;
      extraCommands = ''
        iptables -w -A nixos-fw -p tcp -s 172.16.25.3/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 10.10.10.4/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 6053 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 10201 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 10202 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 10701 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 11434 -j nixos-fw-accept
        # The SOC probes only read-only health/model endpoints. Wyoming audio
        # and every control endpoint remain limited to Home Assistant.
        iptables -w -A nixos-fw -p tcp -s 172.16.25.51/32 -m multiport --dports 10202,10701,11434 -j nixos-fw-accept
        # Herald independently probes the same read-only endpoints so alerts
        # still work when the SOC or Home Assistant is unavailable.
        iptables -w -A nixos-fw -p tcp -s 172.16.25.63/32 -m multiport --dports 10202,10701,11434 -j nixos-fw-accept
      '';
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
