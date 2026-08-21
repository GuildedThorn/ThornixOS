{
  imports = [
    ./monitoring-context.nix
    ./monitoring-base.nix
    ./loki.nix
    ./prometheus.nix
    ./telemetry-nginx.nix
    ./backups.nix
    ./appliance-ingest.nix
    ./grafana.nix
    ./grafana-notifications.nix
    ./grafana-rules.nix
  ];
}
