{ ... }:
{
  networking = {
    hostName = "scout";
    enableIPv6 = false;

    # No static DNS pin: this laptop roams. NetworkManager uses each
    # network's DHCP resolver — pfSense at home (which serves the .arpa
    # names), whatever the local network provides elsewhere.

    # Keep SSH closed while roaming; only the fixed home workstation can enter.
    firewall.extraCommands = ''
      iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 -m mac --mac-source d8:bb:c1:13:9e:4a --dport 22 -j nixos-fw-accept
    '';

  };
  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;

  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
