{ ... }:
{
  networking = {
    hostName = "scout";
    enableIPv6 = false;

    # No static DNS pin: this laptop roams. NetworkManager uses each
    # network's DHCP resolver — pfSense at home (which serves the .arpa
    # names), whatever the local network provides elsewhere.

  };
  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;

  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
