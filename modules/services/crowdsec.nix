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

        # Widen past sshd-only. The `crowdsecurity/linux` collection ships
        # scenarios beyond SSH (su/sudo abuse, generic auth bruteforce) that
        # never saw a line to parse under the old `_SYSTEMD_UNIT=sshd.service`
        # filter — the collection was enabled but starved.
        #
        # Filtering on _TRANSPORT rather than facility, having checked what
        # the journal actually carries: sshd's real auth output arrives as
        # _TRANSPORT=syslog (the entries tagged _TRANSPORT=journal on
        # sshd.service are just systemd's own "Starting SSH Daemon" unit
        # chatter), so this strictly supersets the old filter and picks up
        # sudo/su alongside it.
        #
        # The tempting alternative — SYSLOG_FACILITY=4 (auth) — is a trap
        # here: auditd's events land on facility 4 too and swamp it (~1000 of
        # every 2000 journal entries on a fleet host, now that audit.nix
        # logs execve). CrowdSec's syslog parsers can't read audit records,
        # so that filter would bury the real auth signal in parse failures.
        #
        # Deliberately ONE acquisition rather than adding to the sshd-specific
        # one: overlapping sources feed the same event to a scenario twice,
        # tripping bruteforce thresholds at half their configured count.
        localConfig.acquisitions = [
          {
            source = "journalctl";
            journalctl_filter = [ "_TRANSPORT=syslog" ];
            labels.type = "syslog";
          }
        ];

        # Run a self-contained local LAPI (engine + agent on the same box).
        # Without this the module leaves api.client with a null credentials
        # path and crowdsec dies at startup ("no API client section"). The
        # bootstrap `cscli machine add` writes creds to credentialsFile on
        # first start; the agent then reads them back to reach its own LAPI.
        settings.general.api.server.enable = true;
        # Must live in the crowdsec-owned state dir — /var/lib/crowdsec
        # itself is root:root, so the bootstrap `cscli machine add` can't
        # write the credentials file there (it adds the machine to the DB
        # fine, then fails writing creds one dir too high).
        settings.lapi.credentialsFile = "/var/lib/crowdsec/state/local_api_credentials.yaml";
        # LAPI default 127.0.0.1:8080 collides with the guildedthorn app on
        # websites; move it clear.
        settings.general.api.server.listen_uri = "127.0.0.1:8083";
      };
    };
}
