{ ... }:

{
  networking = {
    hostName = "nixos";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [
      "172.16.25.1" # pfSense — resolves .arpa LAN names
      "1.1.1.1"
    ];

    firewall.allowedTCPPorts = [
      53
      4455
      8500
      5201
      8000
    ];
    firewall.allowedUDPPorts = [
      53
      4455
      8500
      5201
      8000
    ];

    extraHosts = "
      172.16.25.1 pfsense.guildedthorn.arpa
      172.16.25.3 proxmox.guildedthorn.arpa
      172.16.25.4 truenas.guildedthorn.arpa
      ";
  };

  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = true;
  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
