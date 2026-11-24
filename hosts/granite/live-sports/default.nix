{
  config,
  ...
}:
let
  hostname = "livesports.guildedthorn.arpa";
  port = 7000;
in
{
  assertions = [
    {
      assertion = config.networking.hostName == "granite";
      message = "services-live-sports is currently intended for the granite host";
    }
  ];

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # Upstream publishes a multi-arch image from its main branch. Building from
  # source here would repeat the npm install, ICU pin and ncc bundle in every
  # system closure; the published image already contains that build.
  virtualisation.oci-containers.containers.livesports = {
    image = "ghcr.io/rajhodedara/live-sport-plugin:latest";
    ports = [ "127.0.0.1:${toString port}:${toString port}" ];
    environment = {
      PORT = toString port;
      NODE_ENV = "production";
      # Absolute manifest/stream URLs must use the public HTTPS name, not the
      # loopback address nginx proxies from.
      ADDON_URL = "https://${hostname}";
      # Keep the heavy HLS bytes on the same origin as the addon. Split this
      # into a streaming-only name only if the proxy later needs a separate
      # bandwidth budget.
      STREAM_URL = "https://${hostname}";
    };
    volumes = [ "/etc/localtime:/etc/localtime:ro" ];
  };

  # Forgejo owns the shared ACME certificate; add this vhost's name to it.
  thorn.acme.extraDomainNames = [ hostname ];

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts.${hostname} = {
      serverName = hostname;
      forceSSL = true;
      useACMEHost = "forgejo.guildedthorn.arpa";
      extraConfig = ''
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "same-origin" always;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
        # HLS manifests are polled continuously and provider scrapes can be
        # slow; nginx's default buffering and 60s read timeout would both add
        # latency and turn slow upstreams into 504 pages.
        extraConfig = ''
          proxy_buffering off;
          proxy_send_timeout 300s;
          proxy_read_timeout 300s;
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
