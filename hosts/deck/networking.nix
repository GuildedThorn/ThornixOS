{
  networking = {
    hostName = "deck";
    domain = "guildedthorn.arpa";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      extraCommands = ''
        iptables -A nixos-fw -p tcp -s 172.16.25.2 --dport 10700 -j nixos-fw-accept
      '';
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
