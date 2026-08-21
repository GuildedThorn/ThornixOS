{
  config,
  inputs,
  socMonitoring,
  ...
}:
let
  inherit (socMonitoring) telemetryServerCertificate;
in
{
  services.grafana = {
    enable = true;
    settings = {
      server = {
        # TLS via a ThornCloud_CA-signed cert (the fleet already
        # trusts that CA — see security.pki above), so no browser
        # warnings and admin creds/SIEM data don't cross the LAN in
        # cleartext (relevant with MITM lab boxes on the network).
        # Cert lives in the repo; the private key stays in sops.
        # NOTE: soc's deploy needs BOTH certs/soc.guildedthorn.arpa.crt
        # committed AND the grafana_tls_key secret present, or Grafana
        # won't start — add both before pushing this.
        protocol = "https";
        http_addr = "0.0.0.0";
        http_port = 3000;
        domain = "soc.guildedthorn.arpa";
        root_url = "https://soc.guildedthorn.arpa:3000";
        cert_file = telemetryServerCertificate;
        cert_key = config.sops.secrets.grafana_tls_key.path;
        enable_gzip = true;
      };
      security = {
        admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
        secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
        cookie_secure = true;
        cookie_samesite = "strict";
        disable_gravatar = true;
        strict_transport_security = true;
      };
      analytics.reporting_enabled = false;
      analytics.check_for_updates = false;
      analytics.check_for_plugin_updates = false;
      dashboards = {
        default_home_dashboard_path = "${inputs.self}/hosts/soc/dashboards/soc-overview.json";
        min_refresh_interval = "10s";
      };
      metrics.enabled = true;
      snapshots.external_enabled = false;
      users.default_theme = "dark";
      "auth.anonymous".enabled = false;
    };
    provision = {
      enable = true;
      # The datasources originally provisioned without explicit
      # uids; Grafana can't change a uid in place ("data source not
      # found" crash loop), so drop and re-create them each start.
      datasources.settings.deleteDatasources = [
        {
          name = "Loki";
          orgId = 1;
        }
        {
          name = "Prometheus";
          orgId = 1;
        }
      ];
      datasources.settings.datasources = [
        {
          name = "Loki";
          type = "loki";
          uid = "loki";
          url = "http://127.0.0.1:3101";
          jsonData.derivedFields = [
            {
              # Both Suricata EVE and Zeek JSON use this field. The
              # link opens a focused dashboard panel with both data
              # sources filtered to the exact bidirectional flow.
              name = "Community ID";
              # Match both raw JSON log details and the compact
              # line_format output used by the dashboards.
              matcherRegex = ''community_id"?\s*[:=]\s*"?([^"\s]+)'';
              url = "/d/network-visibility/network-visibility?orgId=1&var-community_id=$${__value.raw}&from=now-6h&to=now&viewPanel=32";
              urlDisplayLabel = "Correlate Zeek + Suricata";
            }
          ];
        }
        {
          name = "Prometheus";
          type = "prometheus";
          uid = "prometheus";
          url = "http://127.0.0.1:9091";
          isDefault = true;
        }
      ];

      dashboards.settings.providers = [
        {
          name = "thornix";
          folder = "SIEM";
          # UI tweaks are allowed but live only until the next
          # deploy — the JSON in the repo is the source of truth.
          allowUiUpdates = true;
          options.path = "${inputs.self}/hosts/soc/dashboards";
        }
      ];
    };
  };
}
