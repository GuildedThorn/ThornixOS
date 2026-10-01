{
  # Threadfin M3U/EPG proxy for IPTV
  nixos.modules.services-threadfin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.threadfin;
    in
    {
      options.thorn.threadfin = {
        enable = lib.mkEnableOption "Threadfin M3U/EPG proxy for IPTV";

        port = lib.mkOption {
          type = lib.types.port;
          default = 34400;
          description = "Threadfin web UI and proxy port";
        };

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/threadfin";
          description = "Threadfin data directory (config, logs, cache)";
        };

        m3uUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "https://iptv-org.github.io/iptv/countries/us.m3u";
          description = "M3U playlist URL to proxy";
        };

        epgUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "https://epg.iptv-org.com/epg.xml.gz";
          description = "EPG (XMLTV) URL";
        };

        bufferSize = lib.mkOption {
          type = lib.types.int;
          default = 1024;
          description = "Buffer size in KB for streaming";
        };

        transcoding = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable transcoding (requires ffmpeg)";
        };

        ffmpegPath = lib.mkOption {
          type = lib.types.path;
          default = "/run/current-system/sw/bin/ffmpeg";
          description = "Path to ffmpeg binary for transcoding";
        };

        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Users allowed to access (empty = no auth)";
        };

        logLevel = lib.mkOption {
          type = lib.types.enum [
            "debug"
            "info"
            "warn"
            "error"
          ];
          default = "info";
          description = "Log level";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 threadfin threadfin - -"
          "d ${cfg.dataDir}/logs 0755 threadfin threadfin - -"
        ];

        environment.etc."threadfin/config.json".text = builtins.toJSON {
          logLevel = cfg.logLevel;
          bufferSize = cfg.bufferSize;
          transcoding = cfg.transcoding;
          ffmpegPath = cfg.ffmpegPath;
          users = cfg.users;
          m3u = {
            url = cfg.m3uUrl;
            epgUrl = cfg.epgUrl;
          };
        };

        systemd.services.threadfin = {
          description = "Threadfin M3U/EPG Proxy";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.podman}/bin/podman run --rm --name threadfin \
              -p ${toString cfg.port}:34400 \
              -v ${cfg.dataDir}:/data \
              -v ${cfg.configFile}:/etc/threadfin/config.json:ro \
              --user 1000:1000 \
              ghcr.io/threadfin/threadfin:latest";
            Restart = "on-failure";
            RestartSec = 5;
            User = "threadfin";
            Group = "threadfin";
            StateDirectory = "threadfin";
            LogsDirectory = "threadfin";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
            CapabilityBoundingSet = "";
          };
        };

        users.users.threadfin = {
          isSystemUser = true;
          home = cfg.dataDir;
          description = "Threadfin M3U proxy";
        };

        users.groups.threadfin = { };

        networking.firewall.allowedTCPPorts = [ cfg.port ];

        nginxConfig = lib.mkIf config.thorn.acme.enable {
          services.nginx.virtualHosts."threadfin.${config.networking.domain}" = {
            serverName = "threadfin.${config.networking.domain}";
            forceSSL = true;
            useACMEHost = config.networking.domain;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString cfg.port}";
              proxyWebsockets = true;
            };
          };
        };
      };
    };
}
