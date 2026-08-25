{
  networking = {
    hostName = "deck";
    domain = "guildedthorn.arpa";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      extraCommands = ''
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 6053 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 10201 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 10202 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 10701 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp -s 172.16.25.2/32 --dport 11434 -j nixos-fw-accept
        # The SOC probes only read-only health/model endpoints. Wyoming audio
        # and every control endpoint remain limited to Home Assistant.
        iptables -w -A nixos-fw -p tcp -s 172.16.25.51/32 -m multiport --dports 10202,10701,11434 -j nixos-fw-accept
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
