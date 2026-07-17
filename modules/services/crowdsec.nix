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

        # The LAPI default of 127.0.0.1:8080 collides with the
        # guildedthorn app on websites; keep it well out of the way.
        settings.general.api.server.listen_uri = "127.0.0.1:8083";
      };
    };
}
