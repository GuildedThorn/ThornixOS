{
  nixos.modules.services-observability-roaming =
    { config, ... }:
    {
      assertions = [
        {
          assertion = config.thorn.telemetry.enable;
          message = ''
            services-observability-roaming requires thorn.telemetry.enable
            and an enrolled writer identity.
          '';
        }
      ];

      # Push-based metrics for hosts Prometheus can't scrape (roaming
      # laptops: intermittently online, reachable only over the WireGuard
      # tunnel, deliberately absent from soc's `fleet` scrape list). Alloy
      # scrapes the local node_exporter (enabled by services-observability)
      # and remote-writes to Prometheus on soc; the WAL buffers through
      # offline gaps the same way the Loki journal shipper does.
      #
      # job/instance labels match soc's pull-based "node" job, so the host
      # shows up in the existing Fleet Health dashboards unchanged. The
      # host-down alert (up{job="node"} < 1) stays quiet while the host is
      # offline — the pushed `up` series simply goes stale/NoData — but
      # still fires if node_exporter breaks while the host is up.
      environment.etc."alloy/metrics.alloy".text = ''
        prometheus.scrape "node_local" {
          targets = [{
            __address__ = "127.0.0.1:9100",
            instance    = "${config.networking.hostName}.guildedthorn.arpa:9100",
          }]
          forward_to      = [prometheus.remote_write.soc.receiver]
          job_name        = "node"
          scrape_interval = "30s"
        }

        // comin's metrics, pushed the same way. Roaming hosts are the ones
        // where "is this actually on the pushed config?" is hardest to
        // answer by hand — they're rarely reachable and often behind a
        // captive portal or cellular NAT — so shipping deploy state matters
        // more here than on the always-on hosts, not less.
        prometheus.scrape "comin_local" {
          targets = [{
            __address__ = "127.0.0.1:4243",
            instance    = "${config.networking.hostName}.guildedthorn.arpa:4243",
          }]
          forward_to      = [prometheus.remote_write.soc.receiver]
          job_name        = "comin"
          scrape_interval = "60s"
        }

        prometheus.remote_write "soc" {
          endpoint {
            url = "https://soc.guildedthorn.arpa:9090/api/v1/write"

            tls_config {
              ca_file     = "${config.security.pki.caBundle}"
              cert_file   = "/run/credentials/alloy.service/telemetry-writer.crt"
              key_file    = "/run/credentials/alloy.service/telemetry-writer.key"
              server_name = "soc.guildedthorn.arpa"
              min_version = "TLS12"
            }
          }
        }
      '';
    };
}
