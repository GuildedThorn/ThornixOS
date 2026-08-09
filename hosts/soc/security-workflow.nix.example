# Copy this file to security-workflow.nix only after all three encrypted secrets
# exist in hosts/soc/secrets.yaml. Its presence is the atomic readiness marker
# that enables the local relay and changes Grafana's notification policy.
{ config, ... }:
{
  sops.secrets.thehive_alert_writer_api_key = {
    mode = "0400";
    restartUnits = [ "thorn-security-relay.service" ];
  };
  sops.secrets.opencti_enrichment_reader_token = {
    mode = "0400";
    restartUnits = [ "thorn-security-relay.service" ];
  };
  sops.secrets.grafana_security_webhook_hmac = {
    owner = "grafana";
    mode = "0400";
    restartUnits = [
      "grafana.service"
      "thorn-security-relay.service"
    ];
  };

  thorn.securityWorkflow = {
    enable = true;
    theHiveApiKeyFile = config.sops.secrets.thehive_alert_writer_api_key.path;
    openCtiApiTokenFile = config.sops.secrets.opencti_enrichment_reader_token.path;
    hmacSecretFile = config.sops.secrets.grafana_security_webhook_hmac.path;
  };
}
