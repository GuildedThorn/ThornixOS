{ ... }:
{
  nixos.modules.services-jellyfin =
    {
      config,
      ...
    }:
    let
      hostname = "jellyfin.guildedthorn.arpa";
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "granite";
          message = "services-jellyfin is currently intended for the granite host";
        }
      ];

      services.jellyfin = {
        enable = true;
        dataDir = "/platter/services/jellyfin";
        cacheDir = "/platter/services/jellyfin/cache";
        openFirewall = false;
      };

      # Keep the imported Jellyfin database usable after the TrueNAS-to-NixOS
      # move. Its existing libraries use these old container paths; the links
      # point at the same files on the preserved platter dataset.
      systemd.tmpfiles.rules = [
        # The imported database stores artwork as /config/metadata/... paths.
        "L+ /config - - - - /platter/services/jellyfin"
        "L+ /mnt/movies - - - - /platter/media/Movies"
        "L+ /mnt/anime - - - - /platter/media/Anime"
        "L+ /mnt/shows - - - - /platter/media/Shows"
        "L+ /mnt/music - - - - /platter/media/Music"
      ];

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        virtualHosts.${hostname} = {
          serverName = hostname;
          forceSSL = true;
          # Forgejo owns the shared ACME certificate, which also includes
          # this hostname as an extra SAN.
          useACMEHost = "forgejo.guildedthorn.arpa";
          extraConfig = ''
            add_header Strict-Transport-Security "max-age=31536000" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "same-origin" always;
            client_max_body_size 128m;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:8096";
            proxyWebsockets = true;
          };
        };
      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];
    };
}
