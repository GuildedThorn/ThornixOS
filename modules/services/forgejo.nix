{ ... }:
{
  nixos.modules.services-forgejo =
    {
      config,
      lib,
      ...
    }:
    let
      hostname = "forgejo.guildedthorn.arpa";
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "granite";
          message = "services-forgejo is currently intended for the granite host";
        }
      ];

      services.forgejo = {
        enable = true;
        stateDir = "/platter/services/forgejo";
        database.type = "sqlite3";

        settings = {
          server = {
            DOMAIN = hostname;
            ROOT_URL = "https://${hostname}/";
            HTTP_ADDR = "127.0.0.1";
            HTTP_PORT = 3000;
            DISABLE_SSH = true;
          };

          # Enable registration for the first account; disable it after setup.
          service.DISABLE_REGISTRATION = true;
        };

        dump = {
          enable = true;
          backupDir = "/platter/backups/forgejo";
        };
      };

      thorn.acme = {
        enable = true;
        domain = hostname;
        extraDomainNames = [
          "jellyfin.guildedthorn.arpa"
          "truenas.guildedthorn.arpa"
        ];
        group = config.services.nginx.group;
        reloadServices = [ "nginx.service" ];
      };

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;

        virtualHosts.${hostname} = {
          serverName = hostname;
          forceSSL = true;
          useACMEHost = hostname;
          extraConfig = ''
            add_header Strict-Transport-Security "max-age=31536000" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "same-origin" always;
            client_max_body_size 128m;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:3000";
            proxyWebsockets = true;
          };
        };
      };

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
    };
}
