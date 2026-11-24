{
  config,
  ...
}:
let
  hostname = "musicgrabber.guildedthorn.arpa";
  musicRoot = "/platter/media/Music";
  stateDir = "/platter/services/musicgrabber";
in
{
  assertions = [
    {
      assertion = config.networking.hostName == "granite";
      message = "services-musicgrabber is currently intended for the granite host";
    }
  ];

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.musicgrabber = {
    image = "docker.io/g33kphr33k/musicgrabber:4.6.1";
    # The Jellyfin API key comes from the SOPS-generated env file; the URL is
    # not secret. Host networking makes Jellyfin reachable on loopback and
    # avoids a second listener on qBittorrent's 8080.
    environmentFiles = [ config.sops.templates."musicgrabber.env".path ];
    environment = {
      LISTEN_ADDR = "127.0.0.1";
      LISTEN_PORT = "38274";
      MUSIC_DIR = "/music";
      DB_PATH = "/data/music_grabber.db";
      PUID = "1000";
      PGID = "989";
      JELLYFIN_URL = "http://127.0.0.1:8096";
    };
    volumes = [
      "${musicRoot}:/music"
      "${stateDir}:/data"
      "/etc/localtime:/etc/localtime:ro"
    ];
    # Chromium scrapes large Spotify playlists and needs more than the
    # default 64 MiB of shared memory.
    extraOptions = [
      "--network=host"
      "--shm-size=2gb"
    ];
  };

  systemd.services."podman-musicgrabber" = {
    after = [
      "zfs-import-platter.service"
      "zfs-mount.service"
      "jellyfin.service"
      "sops-nix.service"
    ];
    wants = [
      "jellyfin.service"
      "sops-nix.service"
    ];
  };

  # Match the container's PUID/PGID so downloads land in the media group and
  # Jellyfin can read them through the existing /mnt/music compatibility link.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 1000 989 -"
  ];

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts.${hostname} = {
      serverName = hostname;
      forceSSL = true;
      # Forgejo owns the shared ACME certificate; this name is one of its SANs.
      useACMEHost = "forgejo.guildedthorn.arpa";
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "same-origin" always;
        client_max_body_size 128m;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:38274";
        proxyWebsockets = true;
        # Search results stream in as each source answers.
        extraConfig = ''
          proxy_buffering off;
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
