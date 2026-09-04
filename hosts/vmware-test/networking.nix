{ ... }:
{
  networking = {
    hostName = "vmware-test";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [ "1.1.1.1" ];

    firewall.allowedTCPPorts = [
      22
    ];
  };

  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = false;

  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
