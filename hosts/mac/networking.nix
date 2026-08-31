{ ... }:

{
  networking = {
    hostName = "mac";
    enableIPv6 = false;
    useDHCP = false;

    # enp9s0 is the Intel 82574L at PCI 0000:09:00.0. Keep the management
    # address on the bridge so Proxmox guests can use the physical LAN.
    bridges = {
      vmbr0.interfaces = [ "enp9s0" ];
      vmbr1.interfaces = [ ];
      vmbr2.interfaces = [ ];
    };

    interfaces = {
      enp9s0.useDHCP = false;
      enp10s0.useDHCP = false;
      vmbr0 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "172.16.25.3";
            prefixLength = 24;
          }
        ];
      };
      vmbr1.useDHCP = false;
      vmbr2.useDHCP = false;
    };

    defaultGateway = {
      address = "172.16.25.1";
      interface = "vmbr0";
    };

    # System-wide DNS
    nameservers = [
      "172.16.25.66"
      "172.16.25.2"
      "172.16.25.1"
    ];
    search = [ "guildedthorn.arpa" ];

    # Administration comes from fixed workstations or Scout over WireGuard.
    # SOC retains read-only access to the Proxmox UI for availability probes.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,8006 -s 192.168.1.6/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,8006 -s 192.168.1.74/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp -m multiport --dports 22,8006 -s 10.10.10.4/32 -j nixos-fw-accept
      iptables -w -A nixos-fw -p tcp --dport 8006 -s 172.16.25.51/32 -j nixos-fw-accept
    '';

    networkmanager.enable = false;
  };
}
