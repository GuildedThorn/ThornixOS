{
  # CrowdSec engine, detect-only (SOC Phase 2): scenarios run and alerts
  # land in the journal (and therefore Loki via services-observability),
  # but no bouncer is installed, so nothing is ever blocked. Add
  # services.crowdsec-firewall-bouncer later to start enforcing.
  nixos.modules.services-crowdsec =
    { ... }:
    {
      services.crowdsec = {
        enable = true;
        autoUpdateService = true;

        hub.collections = [
          "crowdsecurity/linux"
          "crowdsecurity/sshd"
        ];

        localConfig.acquisitions = [
          {
            source = "journalctl";
            journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
            labels.type = "syslog";
          }
        ];

        # Run a self-contained local LAPI (engine + agent on the same box).
        # Without this the module leaves api.client with a null credentials
        # path and crowdsec dies at startup ("no API client section"). The
        # bootstrap `cscli machine add` writes creds to credentialsFile on
        # first start; the agent then reads them back to reach its own LAPI.
        settings.general.api.server.enable = true;
        settings.lapi.credentialsFile = "/var/lib/crowdsec/local_api_credentials.yaml";
        # LAPI default 127.0.0.1:8080 collides with the guildedthorn app on
        # websites; move it clear.
        settings.general.api.server.listen_uri = "127.0.0.1:8083";
      };
    };
}
