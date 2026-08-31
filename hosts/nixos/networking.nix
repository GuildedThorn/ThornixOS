{ ... }:

{
  networking = {
    hostName = "nixos";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [ "192.168.1.1" ]; # Unbound resolves internal and public names.

    firewall.allowedTCPPorts = [
      4455
      8500
      5201
      4444
      8000
    ];
    firewall.allowedUDPPorts = [
      4455
      8500
      5201
      4444
      8000
    ];

    extraHosts = "
      172.16.25.1 pfsense.guildedthorn.arpa
      172.16.25.3 proxmox.guildedthorn.arpa
      172.16.25.4 truenas.guildedthorn.arpa
      ";
  };

  networking.networkmanager = {
    enable = true;
    # DHCP-provided public DNS must not precede the internal resolver.
    dns = "none";
    settings.main.no-auto-default = "d8:bb:c1:13:9e:4a";
    ensureProfiles.profiles.nixos-ethernet = {
      connection = {
        id = "NixOS Ethernet";
        type = "ethernet";
        interface-name = "enp42s0";
        autoconnect = true;
      };
      ethernet.mac-address = "d8:bb:c1:13:9e:4a";
      ipv4 = {
        method = "manual";
        addresses = "192.168.1.6/24";
        gateway = "192.168.1.1";
        dns = "192.168.1.1;";
        dns-search = "guildedthorn.arpa;";
        route-metric = 100;
      };
      ipv6.method = "disabled";
    };
  };
}
