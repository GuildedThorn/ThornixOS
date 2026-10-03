{ ... }:
{
  networking = {
    hostName = "scout";
    enableIPv6 = false;

    # No static DNS pin: this laptop roams. NetworkManager uses each
    # network's DHCP resolver — pfSense at home (which serves the .arpa
    # names), whatever the local network provides elsewhere.

    # Keep SSH closed while roaming; only the fixed home workstation can enter.
    # Using nftables now, so rules moved to proper nftables config if needed.
    firewall.extraCommands = "";

  };
  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;

  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
