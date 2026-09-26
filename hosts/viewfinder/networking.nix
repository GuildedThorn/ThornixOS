{
  networking = {
    hostName = "viewfinder";
    domain = "guildedthorn.arpa";
    enableIPv6 = false;
    useDHCP = false;

    # Keep the existing workstation uplink on the Proxmox bridge. Hyprland,
    # OBS, and the capture-card stack remain native services on this host.
    bridges.vmbr0.interfaces = [ "enp6s0" ];
    # Private malware-analysis bridge: no physical interface and no host IP.
    # Only explicitly attached lab VMs can communicate on this segment.
    bridges.vmbr1.interfaces = [ ];
    interfaces = {
      enp6s0.useDHCP = false;
      vmbr0 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "172.16.25.103";
            prefixLength = 24;
          }
        ];
      };
      vmbr1 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "10.77.0.254";
            prefixLength = 24;
          }
        ];
      };
    };
    defaultGateway = {
      address = "172.16.25.1";
      interface = "vmbr0";
    };
    nameservers = [
      "172.16.25.66"
      "172.16.25.2"
      "172.16.25.1"
    ];
    search = [ "guildedthorn.arpa" ];

    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
      ];
      extraCommands = ''
        iptables -w -A nixos-fw -p tcp -s 172.16.25.3/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.3/32 --dport 8006 -j nixos-fw-accept
        iptables -w -A nixos-fw -p udp -s 172.16.25.3/32 --dport 5405:5412 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 --dport 8006 -j nixos-fw-accept
      '';
    };

    networkmanager.enable = false;
  };
}
