{ ... }:

{
  networking = {
    hostName = "mitm";
    domain = "guildedthorn.arpa";
    enableIPv6 = false;

    # System-wide DNS
    nameservers = [
      "172.16.25.1" # pfSense — resolves .arpa LAN names
      "1.1.1.1"
    ];

    firewall = {
      allowedTCPPorts = [ 443 ];
      # The Deck may use MITM's fast Piper voice for short acknowledgements.
      extraCommands = ''
        iptables -w -A nixos-fw -p tcp -s 172.16.25.26/32 --dport 10200 -j nixos-fw-accept
      '';
    };

  };

  networking.networkmanager.enable = false;
}
