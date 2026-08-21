{
  lib,
  socMonitoring,
  ...
}:
let
  inherit (socMonitoring)
    readerOnly
    securityWorkflowReady
    telemetryServerCertificate
    telemetryServerKey
    telemetryVhost
    writerOnly
    ;
in
{
  # Authenticated ingress for the two telemetry backends. Loki and
  # Prometheus remain unauthenticated internally because their only
  # listener is loopback; nginx is the network security boundary.
  # Deliberately enumerate APIs instead of proxying broad prefixes:
  # neither identity can reach delete, admin, status, or lifecycle
  # endpoints over the network.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts = {
      loki-telemetry = (telemetryVhost 3100) // {
        locations = {
          "= /loki/api/v1/push" = {
            proxyPass = "http://127.0.0.1:3101";
            extraConfig = writerOnly;
          };
          "= /loki/api/v1/query" = {
            proxyPass = "http://127.0.0.1:3101";
            extraConfig = readerOnly;
          };
          "= /loki/api/v1/query_range" = {
            proxyPass = "http://127.0.0.1:3101";
            extraConfig = readerOnly;
          };
          "= /loki/api/v1/tail" = {
            proxyPass = "http://127.0.0.1:3101";
            proxyWebsockets = true;
            extraConfig = ''
              if ($ssl_client_s_dn !~ "(^|,)CN=thornix-telemetry-reader(,|$)") {
                return 403;
              }
              if ($request_method != GET) {
                return 405;
              }
            '';
          };
          "/".return = 404;
        };
      };

      prometheus-telemetry = (telemetryVhost 9090) // {
        locations = {
          "= /api/v1/write" = {
            proxyPass = "http://127.0.0.1:9091";
            extraConfig = writerOnly;
          };
          "= /api/v1/query" = {
            proxyPass = "http://127.0.0.1:9091";
            extraConfig = readerOnly;
          };
          "/".return = 404;
        };
      };

      # Loom can ask one purpose-built, read-only endpoint whether
      # model-extracted actors/IOCs appear in recent SIEM evidence or
      # SOC-held OpenCTI reports. Home Assistant can consume the
      # separate bounded operator summary for Deck Voice. nginx
      # authenticates the network source, terminates ThornCloud TLS,
      # and exposes no raw Loki, PromQL, or GraphQL query surface.
      news-correlation-context = lib.mkIf securityWorkflowReady {
        serverName = "soc.guildedthorn.arpa";
        onlySSL = true;
        listen = [
          {
            addr = "0.0.0.0";
            port = 9443;
            ssl = true;
          }
        ];
        sslCertificate = telemetryServerCertificate;
        sslCertificateKey = telemetryServerKey;
        extraConfig = ''
          allow 172.16.25.2;
          allow 172.16.25.62;
          deny all;
          client_max_body_size 32k;
        '';
        locations = {
          "= /api/v1/news-context" = {
            proxyPass = "http://127.0.0.1:9088/news-context";
            extraConfig = ''
              allow 172.16.25.62;
              deny all;
              if ($request_method != POST) {
                return 405;
              }
              proxy_connect_timeout 5s;
              proxy_read_timeout 90s;
              proxy_send_timeout 10s;
            '';
          };
          "= /api/v1/ops-summary" = {
            proxyPass = "http://127.0.0.1:9088/ops-summary";
            extraConfig = ''
              if ($request_method != POST) {
                return 405;
              }
              proxy_connect_timeout 5s;
              proxy_read_timeout 90s;
              proxy_send_timeout 10s;
            '';
          };
          "/".return = 404;
        };
      };
    };
  };

  # Avoid a first-deploy bind race: the old backends must release
  # :3100/:9090 and come back on loopback before nginx claims them.
  systemd.services.nginx = {
    wants = [
      "loki.service"
      "prometheus.service"
    ];
    after = [
      "loki.service"
      "prometheus.service"
    ];
  };
}
