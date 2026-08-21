{
  config,
  lib,
  socMonitoring,
  ...
}:
let
  inherit (socMonitoring)
    blackboxConfig
    blackboxServiceTargets
    fleet
    fleetCominMetricsTargets
    fleetNodeMetricsTargets
    heraldTelemetryReady
    houndTelemetryReady
    loomTelemetryReady
    ;
in
{
  # HTTP/TLS reachability and certificate telemetry for the public
  # site and the LAN services the SOC itself depends on. It listens
  # only on loopback; Prometheus is its sole caller.
  services.prometheus.exporters.blackbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    configFile = blackboxConfig;
  };

  # Metrics stay on the VM disk — small at this fleet size, and
  # object storage for Prometheus means Thanos/Mimir complexity
  # that isn't worth it yet.
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9091;
    retentionTime = "90d";
    # Accept pushed metrics from roaming hosts (scout via
    # services-observability-roaming) that can't be scraped.
    extraFlags = [ "--web.enable-remote-write-receiver" ];
    globalConfig.scrape_interval = "30s";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          { targets = fleetNodeMetricsTargets; }
        ];
        # mac's textfile collector also carries the fast-changing
        # live topology snapshot. Keep it out of the ordinary 30s
        # node job so there is only one copy of those series.
        metric_relabel_configs = [
          {
            source_labels = [ "__name__" ];
            regex = "thorn_topology_.*";
            action = "drop";
          }
        ];
      }
      # Scrape only node_exporter's textfile collector at dashboard
      # speed. This reuses the existing SOC-only :9100 firewall path;
      # no topology HTTP service is exposed from the hypervisor.
      {
        job_name = "topology";
        scrape_interval = "10s";
        scrape_timeout = "5s";
        params."collect[]" = [ "textfile" ];
        static_configs = [
          { targets = [ "proxmox.guildedthorn.arpa:9100" ]; }
        ];
        metric_relabel_configs = [
          {
            source_labels = [ "__name__" ];
            regex = "thorn_topology_.*|node_textfile_(mtime_seconds|scrape_error)";
            action = "keep";
          }
        ];
      }
      # pfSense (node_exporter package). Kept in its own job with an
      # explicit instance label because it's not a flake host, and
      # addressed by IP — pfsense.guildedthorn.arpa's own override
      # oddly resolves to the other subnet (192.168.1.1).
      {
        job_name = "pfsense";
        static_configs = [
          {
            targets = [ "172.16.25.1:9100" ];
            labels.instance = "pfsense.guildedthorn.arpa:9100";
          }
        ];
      }
      # Loki's own metrics — lets us alert when the log pipeline
      # itself breaks (soc going blind is worse than any single
      # host going down, since it's the thing that would tell us).
      {
        job_name = "loki";
        static_configs = [ { targets = [ "127.0.0.1:3101" ]; } ];
      }
      # Monitor the monitoring stack itself. Without these jobs a
      # memory leak, query storm, or failed config reload remains
      # invisible until the service falls over completely.
      {
        job_name = "prometheus";
        scrape_interval = "60s";
        static_configs = [ { targets = [ "127.0.0.1:9091" ]; } ];
      }
      {
        job_name = "grafana";
        # Grafana exposes several thousand internal series; minute
        # resolution is ample and halves their 90-day TSDB cost.
        scrape_interval = "60s";
        scheme = "https";
        tls_config.ca_file = config.security.pki.caBundle;
        static_configs = [ { targets = [ "soc.guildedthorn.arpa:3000" ]; } ];
      }
      # Native NetBox application metrics. nginx exposes only this
      # path to the SOC, and the ThornCloud_CA leaf is verified rather
      # than weakening Prometheus with insecure_skip_verify.
      {
        job_name = "netbox";
        scrape_interval = "60s";
        scheme = "https";
        tls_config = {
          ca_file = config.security.pki.caBundle;
          server_name = "atlas.guildedthorn.arpa";
        };
        static_configs = [ { targets = [ "atlas.guildedthorn.arpa:443" ]; } ];
      }
      # Multi-target exporter pattern: retain the URL as `instance`,
      # pass it to blackbox as `target`, and scrape the local probe.
      {
        job_name = "blackbox-http";
        scrape_interval = "60s";
        metrics_path = "/probe";
        params.module = [ "http_alive" ];
        static_configs = blackboxServiceTargets;
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:9115";
          }
        ];
      }
      # comin — the deploy layer. Everything else scraped here says
      # whether a host is alive; this says whether it's running the
      # config that was pushed. comin_deployment_info carries the
      # deployed commit id as a label, so a stale host is visible
      # rather than something you discover by SSH.
      #
      # Roaming hosts aren't listed: they push this same job over
      # remote-write via services-observability-roaming, using
      # matching job/instance labels so both paths land in one series
      # set.
      {
        job_name = "comin";
        # Deploys are minute-scale at best; scraping faster just adds
        # samples that can't differ.
        scrape_interval = "60s";
        static_configs = [
          { targets = fleetCominMetricsTargets; }
        ];
      }
    ]
    ++ lib.optional houndTelemetryReady {
      # Velociraptor's native Prometheus listener is reachable only
      # from SOC at the host firewall. Keep it separate from node
      # metrics so endpoint connection and collection activity remain
      # easy to query and can use a slower cadence.
      job_name = "velociraptor";
      scrape_interval = "60s";
      static_configs = [ { targets = [ "hound.guildedthorn.arpa:8003" ]; } ];
    }
    ++ lib.optional loomTelemetryReady {
      # n8n exposes application and workflow counters through an
      # exact nginx location available only to SOC. Keep them in a
      # separate job from host metrics and verify the internal CA.
      job_name = "n8n";
      scrape_interval = "60s";
      scheme = "https";
      metrics_path = "/metrics";
      tls_config = {
        ca_file = config.security.pki.caBundle;
        server_name = "loom.guildedthorn.arpa";
      };
      static_configs = [ { targets = [ "loom.guildedthorn.arpa:443" ]; } ];
    }
    ++ lib.optional heraldTelemetryReady {
      # ntfy exposes metrics on a dedicated loopback listener; nginx
      # publishes only the exact path and admits only the SOC host.
      job_name = "ntfy";
      scrape_interval = "60s";
      scheme = "https";
      metrics_path = "/metrics";
      tls_config = {
        ca_file = config.security.pki.caBundle;
        server_name = "herald.guildedthorn.arpa";
      };
      static_configs = [ { targets = [ "herald.guildedthorn.arpa:443" ]; } ];
    };
  };
}
