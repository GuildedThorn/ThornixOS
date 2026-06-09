{ ... }:

{
  networking = {
    hostName = "nixos";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [ "127.0.0.1" ];

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
  };

  # Optional: keep NM for Wi-Fi or VPNs
  networking.networkmanager.enable = false;

  #networking.networkmanager.dns = "none";
  #networking.nameservers = [ "127.0.0.1" ];
}
