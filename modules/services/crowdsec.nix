{
  # CrowdSec engine, detect-only (SOC Phase 2): scenarios run and alerts
  # land in the journal (and therefore Loki via services-observability),
  # but no bouncer is installed, so nothing is ever blocked. Add
  # services.crowdsec-firewall-bouncer later to start enforcing.
  nixos.modules.services-crowdsec =
    { lib, ... }:
    {
      # Upstream bug (observed with the 2026-07 nixpkgs bump): the module's
      # crowdsec-update-hub oneshot runs `systemctl reload crowdsec.service`
      # as its sandboxed DynamicUser, polkit denies it ("requires interactive
      # authentication"), and the unit fails on every host, every timer run.
      # "+" runs the reload with full privileges outside the sandbox; "-"
      # tolerates crowdsec not running yet at boot.
      systemd.services.crowdsec-update-hub.serviceConfig.ExecStartPost =
        lib.mkForce "-+/run/current-system/sw/bin/systemctl reload crowdsec.service";

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
        settings.acquisitions = [
          {
            source = "journalctl";
            journalctl_filter = [ "_TRANSPORT=syslog" ];
            labels.type = "syslog";
          }
        ];

        # Run a self-contained local LAPI (engine + agent on the same box).
        # New module enables the server by default and writes creds next
        # to the DB under config_paths.data_dir, so the setup script's
        # `cscli machines add` bootstrap lands in the same DB the LAPI
        # reads — no override needed.
        # LAPI default 127.0.0.1:8080 collides with the guildedthorn app on
        # websites; move it clear.
        settings.config.api.server.listen_uri = "127.0.0.1:8083";
      };
    };
}
