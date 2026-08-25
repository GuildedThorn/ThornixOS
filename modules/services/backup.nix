{ inputs, ... }:
{
  nixos.modules.services-backup =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.backup;
      hostName = config.networking.hostName;
      backupName = if cfg.name == null then hostName else cfg.name;
      repository =
        if cfg.repository == null then
          "s3:https://truenas.guildedthorn.arpa:30304/${hostName}-backup"
        else
          cfg.repository;
      secretsFile =
        if cfg.secretsFile == null then
          "${inputs.self}/hosts/${hostName}/backup-secrets.yaml"
        else
          cfg.secretsFile;
      resticRuntimeDirectory = "/run/restic-backups-${backupName}";
      activeServicesFile = "${resticRuntimeDirectory}/thorn-active-services";
      backupStateDirectory = "/var/lib/thorn-backup";
      backupReadyMarker = "${backupStateDirectory}/${backupName}.ready";
      metricsDirectory = "/var/lib/node-exporter-textfiles";
      backupMetricsFile = "${metricsDirectory}/thorn-backup-${backupName}.prom";
      restoreMetricsFile = "${metricsDirectory}/thorn-backup-restore-${backupName}.prom";
      allRestorePaths = lib.unique (cfg.restorePaths ++ builtins.attrValues cfg.postgresDumps);
      restoreIncludeArguments = lib.escapeShellArgs (
        lib.concatMap (path: [
          "--include"
          path
        ]) allRestorePaths
      );
      quiesceArguments = lib.escapeShellArgs cfg.quiesceServices;
      hasPostgresDumps = cfg.postgresDumps != { };
      postgresRestoreChecks = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          database: dumpPath:
          let
            testDatabase = "thorn_restore_test_${lib.replaceStrings [ "-" ] [ "_" ] database}";
          in
          ''
            restore_postgresql_dump \
              ${lib.escapeShellArg database} \
              ${lib.escapeShellArg testDatabase} \
              "$RESTORE_ROOT${dumpPath}"
          ''
        ) cfg.postgresDumps
      );
      postgresRestoreFunction = lib.optionalString hasPostgresDumps ''
        restore_postgresql_dump() {
          local source_database=$1
          local test_database=$2
          local dump_path=$3

          if [[ ! "$test_database" =~ ^thorn_restore_test_[a-zA-Z0-9_]+$ ]]; then
            echo "error: unsafe PostgreSQL restore-test database: $test_database" >&2
            exit 1
          fi

          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${config.services.postgresql.package}/bin/dropdb \
              --if-exists --force "$test_database"
          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${config.services.postgresql.package}/bin/createdb "$test_database"
          cleanup_restore_database() {
            ${pkgs.util-linux}/bin/runuser -u postgres -- \
              ${config.services.postgresql.package}/bin/dropdb \
                --if-exists --force "$test_database" >/dev/null 2>&1 || true
          }

          if ! ${pkgs.zstd}/bin/zstd --decompress --stdout "$dump_path" \
            | ${pkgs.util-linux}/bin/runuser -u postgres -- \
                ${config.services.postgresql.package}/bin/psql \
                  --dbname "$test_database" \
                  --set ON_ERROR_STOP=1 \
                  --quiet; then
            cleanup_restore_database
            return 1
          fi
          if ! ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${config.services.postgresql.package}/bin/psql \
                --dbname "$test_database" \
                --tuples-only --no-align \
                --command 'SELECT 1' \
              | ${pkgs.gnugrep}/bin/grep --fixed-strings --line-regexp 1 >/dev/null; then
            cleanup_restore_database
            return 1
          fi
          echo "Restored PostgreSQL database $source_database into $test_database successfully"
          cleanup_restore_database
        }
      '';
      backupPrepare = ''
        set -o errexit -o nounset -o pipefail
        active_services=${lib.escapeShellArg activeServicesFile}
        : > "$active_services"

        ${lib.optionalString (cfg.repository == null) ''
          # SeaweedFS does not create buckets as a side effect of restic init.
          # Establish the per-host bucket before an application is quiesced.
          ${pkgs.rclone}/bin/rclone mkdir :s3:${hostName}-backup \
            --s3-provider Other \
            --s3-env-auth \
            --s3-endpoint https://truenas.guildedthorn.arpa:30304
        ''}

        ${cfg.prepareCommand}

        for unit in ${quiesceArguments}; do
          if ${pkgs.systemd}/bin/systemctl is-active --quiet "$unit"; then
            printf '%s\n' "$unit" >> "$active_services"
            ${pkgs.systemd}/bin/systemctl stop "$unit"
          fi
        done
      '';
      backupCleanup = ''
        set -o nounset -o pipefail
        failed=0
        snapshot_succeeded=0
        if [[ "''${SERVICE_RESULT:-}" == "success" ]]; then
          snapshot_succeeded=1
        fi
        active_services=${lib.escapeShellArg activeServicesFile}
        if [[ -r "$active_services" ]]; then
          while IFS= read -r unit; do
            [[ -n "$unit" ]] || continue
            ${pkgs.systemd}/bin/systemctl start "$unit" || failed=1
          done < "$active_services"
        fi

        run_custom_cleanup() {
          :
          ${cfg.cleanupCommand}
        }
        run_custom_cleanup || failed=1

        record_backup_success() {
          timestamp=$(${pkgs.coreutils}/bin/date +%s)
          marker_tmp=${lib.escapeShellArg "${backupReadyMarker}.tmp"}.$$
          metrics_tmp=${lib.escapeShellArg "${backupMetricsFile}.tmp"}.$$
          : > "$marker_tmp"
          ${pkgs.coreutils}/bin/mv -f "$marker_tmp" ${lib.escapeShellArg backupReadyMarker}
          {
            printf '# HELP thorn_backup_last_success_seconds Unix time of the last proven successful backup.\n'
            printf '# TYPE thorn_backup_last_success_seconds gauge\n'
            printf 'thorn_backup_last_success_seconds{dataset="%s"} %s\n' \
              ${lib.escapeShellArg backupName} "$timestamp"
          } > "$metrics_tmp"
          ${pkgs.coreutils}/bin/chmod 0644 "$metrics_tmp"
          ${pkgs.coreutils}/bin/mv -f "$metrics_tmp" ${lib.escapeShellArg backupMetricsFile}
        }
        if [[ "$snapshot_succeeded" -eq 1 && "$failed" -eq 0 ]]; then
          record_backup_success || failed=1
        fi

        exit "$failed"
      '';
      restoreCheck = pkgs.writeShellScript "thorn-backup-restore-test-${hostName}" ''
        set -o errexit -o nounset -o pipefail

        ${pkgs.restic}/bin/restic check \
          --read-data-subset=${lib.escapeShellArg cfg.checkDataSubset}

        export RESTORE_ROOT="$RUNTIME_DIRECTORY/restore"
        ${pkgs.coreutils}/bin/install -d -m 0700 "$RESTORE_ROOT"
        ${pkgs.restic}/bin/restic restore latest \
          --target "$RESTORE_ROOT" \
          ${restoreIncludeArguments}

        for source_path in ${lib.escapeShellArgs allRestorePaths}; do
          if [[ ! -e "$RESTORE_ROOT$source_path" ]]; then
            echo "error: restored snapshot is missing $source_path" >&2
            exit 1
          fi
        done

        ${postgresRestoreFunction}
        ${postgresRestoreChecks}
        ${cfg.restoreValidationCommand}

        timestamp=$(${pkgs.coreutils}/bin/date +%s)
        metrics_tmp=${lib.escapeShellArg "${restoreMetricsFile}.tmp"}.$$
        {
          printf '# HELP thorn_backup_restore_last_success_seconds Unix time of the last proven successful application-aware restore.\n'
          printf '# TYPE thorn_backup_restore_last_success_seconds gauge\n'
          printf 'thorn_backup_restore_last_success_seconds{dataset="%s"} %s\n' \
            ${lib.escapeShellArg backupName} "$timestamp"
        } > "$metrics_tmp"
        ${pkgs.coreutils}/bin/chmod 0644 "$metrics_tmp"
        ${pkgs.coreutils}/bin/mv -f "$metrics_tmp" ${lib.escapeShellArg restoreMetricsFile}
      '';
    in
    {
      options.thorn.backup = {
        enable = lib.mkEnableOption "encrypted off-host service-state backups";
        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Restic backup name; defaults to the host name.";
        };
        repository = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Restic repository URL; defaults to a per-host SeaweedFS bucket.";
        };
        secretsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "SOPS file with per-host restic and S3 credentials.";
        };
        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Authoritative paths included in the off-host backup.";
        };
        exclude = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Restic exclude patterns for rebuildable or transient data.";
        };
        schedule = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 04:00:00";
          description = "OnCalendar expression for the daily backup.";
        };
        quiesceServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Services stopped only while restic snapshots live database files.";
        };
        prepareCommand = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Command run before optional service quiescing.";
        };
        cleanupCommand = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Command run after quiesced services have been restarted.";
        };
        restorePaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Representative files restored during the weekly recovery test.";
        };
        postgresDumps = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Database names mapped to compressed logical dumps for real test restores.";
        };
        restoreValidationCommand = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Additional validation run against RESTORE_ROOT after recovery.";
        };
        checkDataSubset = lib.mkOption {
          type = lib.types.str;
          default = "5%";
          description = "Repository payload fraction read by the weekly restic check.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.paths != [ ];
            message = "thorn.backup.paths must contain authoritative service state";
          }
          {
            assertion = allRestorePaths != [ ];
            message = "thorn.backup needs a representative restore path or PostgreSQL dump";
          }
          {
            assertion = builtins.pathExists secretsFile;
            message = "Missing per-host encrypted backup credentials: ${secretsFile}";
          }
          {
            assertion = builtins.match "[a-z0-9][a-z0-9-]*" backupName != null;
            message = "thorn.backup.name must be safe for service, metric, and state names";
          }
        ];

        sops.secrets = {
          thorn_backup_restic_password = {
            sopsFile = secretsFile;
            restartUnits = [ "thorn-backup-restore-test.service" ];
          };
          thorn_backup_s3_access_key_id.sopsFile = secretsFile;
          thorn_backup_s3_secret_access_key.sopsFile = secretsFile;
        };
        sops.templates."thorn-backup-s3.env" = {
          content = ''
            AWS_ACCESS_KEY_ID=${config.sops.placeholder.thorn_backup_s3_access_key_id}
            AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.thorn_backup_s3_secret_access_key}
          '';
        };

        services.restic.backups.${backupName} = {
          initialize = true;
          inherit repository;
          passwordFile = config.sops.secrets.thorn_backup_restic_password.path;
          environmentFile = config.sops.templates."thorn-backup-s3.env".path;
          paths = cfg.paths;
          exclude = cfg.exclude;
          backupPrepareCommand = backupPrepare;
          backupCleanupCommand = backupCleanup;
          extraBackupArgs = [ "--compression=max" ];
          timerConfig = {
            OnCalendar = cfg.schedule;
            RandomizedDelaySec = "10m";
            Persistent = true;
          };
          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 5"
            "--keep-monthly 6"
            "--keep-yearly 2"
          ];
        };

        systemd.services."restic-backups-${backupName}".serviceConfig.TimeoutStartSec = "2h";

        systemd.services.thorn-backup-restore-test = {
          description = "Read backup payloads and test service-state recovery";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ] ++ lib.optional hasPostgresDumps "postgresql.service";
          unitConfig.ConditionPathExists = backupReadyMarker;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = restoreCheck;
            EnvironmentFile = config.sops.templates."thorn-backup-s3.env".path;
            Environment = [
              "RESTIC_REPOSITORY=${repository}"
              "RESTIC_PASSWORD_FILE=${config.sops.secrets.thorn_backup_restic_password.path}"
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
          };
        };
        systemd.timers.thorn-backup-restore-test = {
          description = "Weekly application-aware backup restore test";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "Sun *-*-* 10:00:00";
            RandomizedDelaySec = "4h";
            Persistent = true;
            Unit = "thorn-backup-restore-test.service";
          };
        };
      };
    };
}
