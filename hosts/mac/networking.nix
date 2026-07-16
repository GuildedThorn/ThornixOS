{ ... }:

{
  networking = {
    hostName = "mac";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [
      "172.16.25.1" # pfSense — resolves .arpa LAN names
      "1.1.1.1"
    ];

    firewall.allowedTCPPorts = [
      22
      8006
    ];
    firewall.allowedUDPPorts = [
      22
      8006
    ];
  };

  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = false;

  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
