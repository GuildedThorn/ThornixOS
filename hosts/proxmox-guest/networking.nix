{ ... }:
{
  networking = {
    hostName = "proxmox-guest";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [
      "172.16.25.1" # pfSense — resolves .arpa LAN names
      "1.1.1.1"
    ];

    firewall.allowedTCPPorts = [
      22
    ];
    firewall.allowedUDPPorts = [
      22
    ];
  };

  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = true;

  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
