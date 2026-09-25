{ ... }:
{
  nixos.modules.services-media-arr =
    {
      config,
      lib,
      ...
    }:
    let
      qbitHost = "qbittorrent.guildedthorn.arpa";
      prowlarrHost = "prowlarr.guildedthorn.arpa";
      seerrHost = "seerr.guildedthorn.arpa";
      sonarrHost = "sonarr.guildedthorn.arpa";
      radarrHost = "radarr.guildedthorn.arpa";
      mediaGroup = "media";
      downloadRoot = "/platter/downloads";
      mediaRoot = "/platter/media";
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "granite";
          message = "services-media-arr is currently intended for the granite host";
        }
      ];

      users.groups.${mediaGroup} = { };
      users.users.prowlarr = {
        isSystemUser = true;
        group = mediaGroup;
        home = "/platter/services/prowlarr";
        createHome = false;
      };

      services.qbittorrent = {
        enable = true;
        user = "qbittorrent";
        group = mediaGroup;
        profileDir = "/platter/services/qbittorrent";
        webuiPort = 8080;
        torrentingPort = 51413;
        openFirewall = false;
        serverConfig = {
          Session = {
            DefaultSavePath = "${downloadRoot}/complete";
            TempPath = "${downloadRoot}/incomplete";
          };
        };
      };

      services.sonarr = {
        enable = true;
        user = "sonarr";
        group = mediaGroup;
        dataDir = "/platter/services/sonarr";
        openFirewall = false;
      };

      services.radarr = {
        enable = true;
        user = "radarr";
        group = mediaGroup;
        dataDir = "/platter/services/radarr";
        openFirewall = false;
      };

      systemd.services.qbittorrent.serviceConfig.UMask = lib.mkForce "0007";
      systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0007";
      systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0007";

      services.prowlarr = {
        enable = true;
        dataDir = "/platter/services/prowlarr";
        openFirewall = false;
      };

      systemd.services.prowlarr.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "prowlarr";
        Group = mediaGroup;
      };

      services.seerr = {
        enable = true;
        # Seerr's database/config is small; keep it on the native state
        # filesystem so service sandbox setup does not depend on platter's
        # mount ordering.
        configDir = "/var/lib/seerr";
        port = 5055;
        openFirewall = false;
      };

      # The current Seerr module's strict filesystem sandbox also makes its
      # /var/lib state path read-only. Keep the rest of the system protected,
      # while allowing Seerr's normal local application state to be created.
      systemd.services.seerr.serviceConfig = {
        ProtectSystem = lib.mkForce "full";
        StateDirectory = lib.mkForce "seerr";
        StateDirectoryMode = "0750";
      };

      # Only Prowlarr needs this local helper. Do not expose it through Nginx
      # or the firewall; FlareSolverr is an HTTP automation endpoint.
      services.flaresolverr = {
        enable = true;
        port = 8191;
        openFirewall = false;
      };

      # Byparr exposes the FlareSolverr-compatible API on a separate local
      # port so Prowlarr can test it without removing the existing fallback.
      virtualisation.oci-containers.containers.byparr = {
        image = "ghcr.io/thephaseless/byparr:latest";
        ports = [ "127.0.0.1:8192:8191" ];
        environment = {
          HOST = "0.0.0.0";
          PORT = "8191";
          BROWSER_LOCALE = "en-US";
        };
        extraOptions = [ "--shm-size=512m" ];
      };

      systemd.tmpfiles.rules = [
        "d ${downloadRoot} 2770 root ${mediaGroup} -"
        "d ${downloadRoot}/incomplete 2770 root ${mediaGroup} -"
        "d ${downloadRoot}/complete 2770 root ${mediaGroup} -"
        "d ${downloadRoot}/complete/sonarr 2770 root ${mediaGroup} -"
        "d ${downloadRoot}/complete/radarr 2770 root ${mediaGroup} -"
        "d ${mediaRoot} 2770 root ${mediaGroup} -"
        "d /platter/services/qbittorrent 0750 qbittorrent ${mediaGroup} -"
        "d /platter/services/sonarr 0750 sonarr ${mediaGroup} -"
        "d /platter/services/radarr 0750 radarr ${mediaGroup} -"
        "d /platter/services/prowlarr 0750 prowlarr ${mediaGroup} -"
      ];

      services.nginx.virtualHosts = {
        ${qbitHost} = {
          serverName = qbitHost;
          forceSSL = true;
          useACMEHost = "forgejo.guildedthorn.arpa";
          locations."/".proxyPass = "http://127.0.0.1:8080";
        };
        ${sonarrHost} = {
          serverName = sonarrHost;
          forceSSL = true;
          useACMEHost = "forgejo.guildedthorn.arpa";
          locations."/".proxyPass = "http://127.0.0.1:8989";
        };
        ${prowlarrHost} = {
          serverName = prowlarrHost;
          forceSSL = true;
          useACMEHost = "forgejo.guildedthorn.arpa";
          locations."/".proxyPass = "http://127.0.0.1:9696";
        };
        ${seerrHost} = {
          serverName = seerrHost;
          forceSSL = true;
          useACMEHost = "forgejo.guildedthorn.arpa";
          locations."/".proxyPass = "http://127.0.0.1:5055";
        };
        ${radarrHost} = {
          serverName = radarrHost;
          forceSSL = true;
          useACMEHost = "forgejo.guildedthorn.arpa";
          locations."/".proxyPass = "http://127.0.0.1:7878";
        };
      };

      networking.firewall.allowedTCPPorts = [ 51413 ];
    };
}
