{
  nixos.modules.services-observability-roaming =
    { config, ... }:
    {
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

        prometheus.remote_write "soc" {
          endpoint {
            url = "http://soc.guildedthorn.arpa:9090/api/v1/write"
          }
        }
      '';
    };
}
