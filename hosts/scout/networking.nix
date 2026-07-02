{ ... }:
{
  networking = {
    hostName = "scout";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [ "1.1.1.1" ];

    firewall.allowedTCPPorts = [
      53
    ];
    firewall.allowedUDPPorts = [
      53
    ];

  };
  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;

  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
