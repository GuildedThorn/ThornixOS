{ config, ... }:
let
  root = "/platter/services/reference";
  port = 8083;
  graniteAddress = "172.16.25.4";
  mitmAddress = "172.16.25.2";
in
{
  assertions = [
    {
      assertion = config.networking.hostName == "granite";
      message = "offline reference data is currently intended for the granite host";
    }
  ];

  # RFC text is a manual download, kept out of the Nix store. It is served on
  # Granite's LAN address (the firewall below restricts clients to MITM); MITM
  # proxies it on wiki.guildedthorn.arpa/rfc/. The maps module owns /maps/.
  # Populate with:
  #   sudo rsync -avz rsync.rfc-editor.org::rfcs-text-only \
  #     /platter/services/reference/rfc/
  systemd.tmpfiles.rules = [
    "d ${root}/rfc 0755 root root -"
  ];

  services.nginx = {
    enable = true;
    virtualHosts."reference-internal" = {
      listen = [
        {
          addr = graniteAddress;
          port = port;
        }
      ];
      locations."/rfc/" = {
        alias = "${root}/rfc/";
        extraConfig = ''
          autoindex on;
          autoindex_exact_size off;
        '';
      };
    };
  };

  networking.firewall.extraCommands = ''
    iptables -w -A nixos-fw -p tcp -s ${mitmAddress}/32 \
      --dport ${toString port} -j nixos-fw-accept
  '';
}
