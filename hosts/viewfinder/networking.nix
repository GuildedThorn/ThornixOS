{
  networking = {
    hostName = "viewfinder";
    domain = "guildedthorn.arpa";
    networkmanager = {
      enable = true;
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
      ];
      extraCommands = ''
        iptables -w -A nixos-fw -p tcp -s 172.16.25.3/32 --dport 22 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 192.168.1.6/32 --dport 22 -j nixos-fw-accept
      '';
    };
  };
}
