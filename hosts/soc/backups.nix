{
  config,
  pkgs,
  socMonitoring,
  ...
}:
let
  inherit (socMonitoring) seaweedfsS3;
in
{
  # Prometheus TSDB backup to the NAS. Loki's chunks already live in
  # object storage, so soc has always been "rebuildable without data
  # loss" for LOGS only — metrics sat on the VM disk with no copy
  # anywhere, and a rebuild silently took 90 days of history with it.
  #
  # Backing up the data directory directly rather than enabling
  # Prometheus's admin API solely for snapshots. nginx would keep the
  # route off the network, but an unnecessary destructive API is still
  # avoidable local attack surface.
  #
  # The cost of that choice: TSDB blocks are immutable once written,
  # but the in-memory head is flushed through a live WAL, so a
  # restic run can capture a torn tail. Prometheus truncates a
  # partial WAL on replay, so a restore loses at most the last
  # (unflushed) couple of hours rather than failing to start.
  services.restic.backups.prometheus = {
    initialize = true;
    repository = "s3:https://${seaweedfsS3}/prometheus-backup";
    passwordFile = config.sops.secrets.restic_password.path;
    environmentFile = config.sops.templates."restic-s3.env".path;
    paths = [
      "/var/lib/${config.services.prometheus.stateDir}"
      "/var/lib/grafana"
    ];
    backupPrepareCommand = ''
      set -o errexit -o nounset -o pipefail
      ${pkgs.rclone}/bin/rclone mkdir :s3:prometheus-backup \
        --s3-provider Other \
        --s3-env-auth \
        --s3-endpoint https://${seaweedfsS3}
    '';
    backupCleanupCommand = ''
      set -o errexit -o nounset -o pipefail
      if [[ "''${SERVICE_RESULT:-}" == "success" ]]; then
        timestamp=$(${pkgs.coreutils}/bin/date +%s)
        marker_tmp=/var/lib/thorn-backup/soc.ready.tmp.$$
        metrics_tmp=/var/lib/node-exporter-textfiles/thorn-backup-soc.prom.tmp.$$
        : > "$marker_tmp"
        ${pkgs.coreutils}/bin/mv -f "$marker_tmp" /var/lib/thorn-backup/soc.ready
        {
          printf '# HELP thorn_backup_last_success_seconds Unix time of the last proven successful backup.\n'
          printf '# TYPE thorn_backup_last_success_seconds gauge\n'
          printf 'thorn_backup_last_success_seconds{dataset="soc"} %s\n' "$timestamp"
        } > "$metrics_tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$metrics_tmp"
        ${pkgs.coreutils}/bin/mv -f "$metrics_tmp" \
          /var/lib/node-exporter-textfiles/thorn-backup-soc.prom
      fi
    '';
    timerConfig = {
      OnCalendar = "daily";
      # Spread load off the top of the hour; Persistent catches up a
      # run the VM slept through.
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 3"
    ];
  };

  systemd.services.restic-backups-prometheus.serviceConfig.TimeoutStartSec = "2h";

  systemd.services.thorn-backup-restore-test = {
    description = "Read SOC backup payloads and test Grafana recovery";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "/var/lib/thorn-backup/soc.ready";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.templates."restic-s3.env".path;
      Environment = [
        "RESTIC_REPOSITORY=s3:https://${seaweedfsS3}/prometheus-backup"
        "RESTIC_PASSWORD_FILE=${config.sops.secrets.restic_password.path}"
        "XDG_CACHE_HOME=/var/cache/thorn-backup-restore-test"
      ];
      RuntimeDirectory = "thorn-backup-restore-test";
      RuntimeDirectoryMode = "0700";
      CacheDirectory = "thorn-backup-restore-test";
      CacheDirectoryMode = "0700";
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "2h";
      UMask = "0077";
      ExecStart = pkgs.writeShellScript "soc-backup-restore-test" ''
        set -o errexit -o nounset -o pipefail

        ${pkgs.restic}/bin/restic check --read-data-subset=5%

        restore_root="$RUNTIME_DIRECTORY/restore"
        ${pkgs.coreutils}/bin/install -d -m 0700 "$restore_root"
        ${pkgs.restic}/bin/restic restore latest \
          --target "$restore_root" \
          --include /var/lib/grafana/data/grafana.db

        database="$restore_root/var/lib/grafana/data/grafana.db"
        [[ -s "$database" ]]
        ${pkgs.sqlite}/bin/sqlite3 "$database" \
          'PRAGMA integrity_check;' \
          | ${pkgs.gnugrep}/bin/grep \
            --fixed-strings --line-regexp ok >/dev/null

        timestamp=$(${pkgs.coreutils}/bin/date +%s)
        metrics_tmp=/var/lib/node-exporter-textfiles/thorn-backup-restore-soc.prom.tmp.$$
        {
          printf '# HELP thorn_backup_restore_last_success_seconds Unix time of the last proven successful application-aware restore.\n'
          printf '# TYPE thorn_backup_restore_last_success_seconds gauge\n'
          printf 'thorn_backup_restore_last_success_seconds{dataset="soc"} %s\n' "$timestamp"
        } > "$metrics_tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$metrics_tmp"
        ${pkgs.coreutils}/bin/mv -f "$metrics_tmp" \
          /var/lib/node-exporter-textfiles/thorn-backup-restore-soc.prom
      '';
    };
  };

  systemd.timers.thorn-backup-restore-test = {
    description = "Weekly SOC backup restore test";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 10:00:00";
      RandomizedDelaySec = "4h";
      Persistent = true;
      Unit = "thorn-backup-restore-test.service";
    };
  };

  # An external dead-man switch for the monitoring host itself. A
  # success ping is sent only after the local SOC services and their
  # HTTP readiness endpoints pass. Local failures are reported
  # immediately; loss of the VM, hypervisor, power, LAN, or internet
  # is detected by Healthchecks when the success pings stop.
  systemd.services.soc-deadman = {
    description = "Verify SOC health and send external heartbeat";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.curl
      pkgs.systemd
    ];
    script = ''
      set -u
      source ${config.sops.templates."healthchecks.env".path}

      failed=0

      systemctl is-active --quiet \
        loki prometheus grafana alloy nginx syslog || failed=1

      curl -fsS --max-time 5 \
        http://127.0.0.1:3101/ready >/dev/null || failed=1

      curl -fsS --max-time 5 \
        http://127.0.0.1:9091/-/ready >/dev/null || failed=1

      curl -fsS --max-time 5 \
        --resolve soc.guildedthorn.arpa:3000:127.0.0.1 \
        https://soc.guildedthorn.arpa:3000/api/health \
        >/dev/null || failed=1

      if (( failed != 0 )); then
        curl -fsS --retry 2 --max-time 10 \
          "$HEALTHCHECKS_URL/fail" >/dev/null || true
        exit 1
      fi

      curl -fsS --retry 2 --max-time 10 \
        "$HEALTHCHECKS_URL" >/dev/null
    '';
    serviceConfig.Type = "oneshot";
  };

  systemd.timers.soc-deadman = {
    description = "Run SOC external heartbeat";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      RandomizedDelaySec = "15s";
      Unit = "soc-deadman.service";
    };
  };
}
