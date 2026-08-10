{ inputs, ... }:
{
  nixos.modules.services-opencti =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "oracle.guildedthorn.arpa";
      stateDirectory = "/var/lib/oracle";
      secretsFile = "${stateDirectory}/secrets.env";
      adminPasswordFile = "${stateDirectory}/admin-initial-password";
      runtimeDirectory = "/run/oracle";
      secretsReadyMarker = "${runtimeDirectory}/secrets-ready";
      lockFile = "/run/lock/oracle-opencti.lock";

      composeFile = pkgs.writeText "thornix-oracle-opencti-compose.yaml" (
        builtins.readFile ./oracle-compose.yaml
      );
      compose = "${pkgs.docker-compose}/bin/docker-compose --env-file ${secretsFile} --project-name thornix-oracle --file ${composeFile}";

      composeCheckEnvironment = pkgs.writeText "oracle-compose-check.env" ''
        MINIO_ROOT_USER=opencti
        MINIO_ROOT_PASSWORD=compose-check-only
        RABBITMQ_DEFAULT_USER=opencti
        RABBITMQ_DEFAULT_PASS=compose-check-only
        OPENCTI_ADMIN_EMAIL=admin@guildedthorn.com
        OPENCTI_ADMIN_PASSWORD=compose-check-only
        OPENCTI_ADMIN_TOKEN=00000000-0000-4000-8000-000000000001
        OPENCTI_ENCRYPTION_KEY=compose-check-only
        OPENCTI_HEALTHCHECK_ACCESS_KEY=00000000-0000-4000-8000-000000000002
        CONNECTOR_OPENCTI_ID=00000000-0000-4000-8000-000000000003
        CONNECTOR_MITRE_ID=00000000-0000-4000-8000-000000000004
        CONNECTOR_CISA_KEV_ID=00000000-0000-4000-8000-000000000005
        CONNECTOR_THREATFOX_ID=00000000-0000-4000-8000-000000000006
        CONNECTOR_FIRST_EPSS_ID=00000000-0000-4000-8000-000000000007
      '';
      composeCheck =
        pkgs.runCommand "oracle-opencti-compose-check" { nativeBuildInputs = [ pkgs.docker-compose ]; }
          ''
            export HOME="$TMPDIR"
            docker-compose --env-file ${composeCheckEnvironment} \
              --project-name thornix-oracle --file ${composeFile} config --quiet
            touch "$out"
          '';

      prepare = pkgs.writeShellScript "oracle-opencti-prepare" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        if [[ ! -s ${lib.escapeShellArg secretsFile} ]]; then
          temporary_secrets=$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${stateDirectory}/.secrets.env.XXXXXX"})
          trap '${pkgs.coreutils}/bin/rm -f -- "$temporary_secrets"' EXIT

          minio_password=$(${lib.getExe pkgs.openssl} rand -hex 32)
          rabbitmq_password=$(${lib.getExe pkgs.openssl} rand -hex 32)
          admin_password=$(${lib.getExe pkgs.openssl} rand -base64 36 | ${pkgs.coreutils}/bin/tr -d '\n')
          admin_token=$(${pkgs.util-linux}/bin/uuidgen)
          encryption_key=$(${lib.getExe pkgs.openssl} rand -base64 32 | ${pkgs.coreutils}/bin/tr -d '\n')
          health_access_key=$(${pkgs.util-linux}/bin/uuidgen)
          connector_opencti_id=$(${pkgs.util-linux}/bin/uuidgen)
          connector_mitre_id=$(${pkgs.util-linux}/bin/uuidgen)
          connector_cisa_kev_id=$(${pkgs.util-linux}/bin/uuidgen)
          connector_threatfox_id=$(${pkgs.util-linux}/bin/uuidgen)
          connector_first_epss_id=$(${pkgs.util-linux}/bin/uuidgen)

          {
            printf 'MINIO_ROOT_USER=opencti\n'
            printf 'MINIO_ROOT_PASSWORD=%s\n' "$minio_password"
            printf 'RABBITMQ_DEFAULT_USER=opencti\n'
            printf 'RABBITMQ_DEFAULT_PASS=%s\n' "$rabbitmq_password"
            printf 'OPENCTI_ADMIN_EMAIL=admin@guildedthorn.com\n'
            printf 'OPENCTI_ADMIN_PASSWORD=%s\n' "$admin_password"
            printf 'OPENCTI_ADMIN_TOKEN=%s\n' "$admin_token"
            printf 'OPENCTI_ENCRYPTION_KEY=%s\n' "$encryption_key"
            printf 'OPENCTI_HEALTHCHECK_ACCESS_KEY=%s\n' "$health_access_key"
            printf 'CONNECTOR_OPENCTI_ID=%s\n' "$connector_opencti_id"
            printf 'CONNECTOR_MITRE_ID=%s\n' "$connector_mitre_id"
            printf 'CONNECTOR_CISA_KEV_ID=%s\n' "$connector_cisa_kev_id"
            printf 'CONNECTOR_THREATFOX_ID=%s\n' "$connector_threatfox_id"
            printf 'CONNECTOR_FIRST_EPSS_ID=%s\n' "$connector_first_epss_id"
          } > "$temporary_secrets"

          printf '%s\n' "$admin_password" > ${lib.escapeShellArg adminPasswordFile}
          ${pkgs.coreutils}/bin/chmod 0600 "$temporary_secrets" ${lib.escapeShellArg adminPasswordFile}
          ${pkgs.coreutils}/bin/mv -- "$temporary_secrets" ${lib.escapeShellArg secretsFile}
          trap - EXIT
        fi

        # shellcheck disable=SC1090
        source ${lib.escapeShellArg secretsFile}
        : "''${MINIO_ROOT_USER:?missing MINIO_ROOT_USER}"
        : "''${MINIO_ROOT_PASSWORD:?missing MINIO_ROOT_PASSWORD}"
        : "''${RABBITMQ_DEFAULT_USER:?missing RABBITMQ_DEFAULT_USER}"
        : "''${RABBITMQ_DEFAULT_PASS:?missing RABBITMQ_DEFAULT_PASS}"
        : "''${OPENCTI_ADMIN_EMAIL:?missing OPENCTI_ADMIN_EMAIL}"
        : "''${OPENCTI_ADMIN_PASSWORD:?missing OPENCTI_ADMIN_PASSWORD}"
        : "''${OPENCTI_ADMIN_TOKEN:?missing OPENCTI_ADMIN_TOKEN}"
        : "''${OPENCTI_ENCRYPTION_KEY:?missing OPENCTI_ENCRYPTION_KEY}"
        : "''${OPENCTI_HEALTHCHECK_ACCESS_KEY:?missing OPENCTI_HEALTHCHECK_ACCESS_KEY}"
        : "''${CONNECTOR_OPENCTI_ID:?missing CONNECTOR_OPENCTI_ID}"
        : "''${CONNECTOR_MITRE_ID:?missing CONNECTOR_MITRE_ID}"

        # Existing Oracle installs predate these feed connectors. Extend the
        # persistent environment in place so deployment adds stable connector
        # identities without rotating any platform or database credential.
        if [[ -z "''${CONNECTOR_CISA_KEV_ID:-}" ]]; then
          printf 'CONNECTOR_CISA_KEV_ID=%s\n' "$(${pkgs.util-linux}/bin/uuidgen)" >> ${lib.escapeShellArg secretsFile}
        fi
        if [[ -z "''${CONNECTOR_THREATFOX_ID:-}" ]]; then
          printf 'CONNECTOR_THREATFOX_ID=%s\n' "$(${pkgs.util-linux}/bin/uuidgen)" >> ${lib.escapeShellArg secretsFile}
        fi
        if [[ -z "''${CONNECTOR_FIRST_EPSS_ID:-}" ]]; then
          printf 'CONNECTOR_FIRST_EPSS_ID=%s\n' "$(${pkgs.util-linux}/bin/uuidgen)" >> ${lib.escapeShellArg secretsFile}
        fi

        # shellcheck disable=SC1090
        source ${lib.escapeShellArg secretsFile}
        : "''${CONNECTOR_CISA_KEV_ID:?missing CONNECTOR_CISA_KEV_ID}"
        : "''${CONNECTOR_THREATFOX_ID:?missing CONNECTOR_THREATFOX_ID}"
        : "''${CONNECTOR_FIRST_EPSS_ID:?missing CONNECTOR_FIRST_EPSS_ID}"

        if [[ ! -s ${lib.escapeShellArg adminPasswordFile} ]]; then
          printf '%s\n' "$OPENCTI_ADMIN_PASSWORD" > ${lib.escapeShellArg adminPasswordFile}
          ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg adminPasswordFile}
        fi

        ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg secretsReadyMarker}
        ${pkgs.coreutils}/bin/chmod 0444 ${lib.escapeShellArg secretsReadyMarker}
      '';

      stackStart = pkgs.writeShellScript "oracle-opencti-start" ''
        set -o errexit -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 3600 9
        exec ${compose} up --detach --remove-orphans
      '';

      stackStop = pkgs.writeShellScript "oracle-opencti-stop" ''
        set -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 60 9 || exit 0
        exec ${compose} stop --timeout 90
      '';

      healthCheck = pkgs.writeShellScript "oracle-opencti-health" ''
        set -o errexit -o nounset -o pipefail

        for service in \
          redis elasticsearch minio rabbitmq opencti worker \
          connector-opencti connector-mitre connector-cisa-kev \
          connector-threatfox connector-first-epss
        do
          container_id=$(${compose} ps --quiet --status running "$service")
          if [[ -z "$container_id" ]]; then
            echo "error: critical Oracle container is not running: $service" >&2
            exit 1
          fi
        done

        # shellcheck disable=SC1090
        source ${lib.escapeShellArg secretsFile}
        ${pkgs.curl}/bin/curl --fail --silent --show-error \
          --connect-timeout 3 --max-time 30 --output /dev/null \
          --cacert ${inputs.self}/certs/ThornCloud_CA.crt \
          --resolve ${hostname}:443:127.0.0.1 \
          "https://${hostname}/health?health_access_key=$OPENCTI_HEALTHCHECK_ACCESS_KEY"
      '';

      composeCommand = pkgs.writeShellApplication {
        name = "oracle-compose";
        runtimeInputs = [ pkgs.docker-compose ];
        text = ''
          if ((EUID != 0)); then
            echo "error: oracle-compose must run as root" >&2
            exit 1
          fi
          exec ${compose} "$@"
        '';
      };

      adminPasswordCommand = pkgs.writeShellApplication {
        name = "oracle-admin-password";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if ((EUID != 0)); then
            echo "error: oracle-admin-password must run as root" >&2
            exit 1
          fi
          if [[ ! -s ${lib.escapeShellArg adminPasswordFile} ]]; then
            echo "error: Oracle has not generated its administrator credential" >&2
            exit 1
          fi

          printf 'Username: admin@guildedthorn.com\nPassword: '
          cat ${lib.escapeShellArg adminPasswordFile}
          echo "Change this generated bootstrap password after first login; this local copy will then be stale."
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "oracle";
          message = "services-opencti is a fixed service profile for the oracle host";
        }
        {
          assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          message = "Oracle's reviewed container image digests are pinned for linux/amd64";
        }
      ];

      system.checks = [ composeCheck ];
      boot.kernel.sysctl."vm.max_map_count" = 1048575;

      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
        daemon.settings = {
          "live-restore" = true;
          "log-driver" = "journald";
          "userland-proxy" = false;
        };
      };

      environment = {
        etc."oracle/rabbitmq.conf".text = ''
          max_message_size = 536870912
          consumer_timeout = 3600000
        '';
        systemPackages = [
          adminPasswordCommand
          composeCommand
        ];
      };

      systemd.services = {
        oracle-opencti-prepare = {
          description = "Generate Oracle OpenCTI runtime secrets";
          wantedBy = [ "multi-user.target" ];
          before = [ "oracle-opencti.service" ];
          restartTriggers = [ prepare ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = prepare;
            StateDirectory = "oracle";
            StateDirectoryMode = "0700";
            RuntimeDirectory = "oracle";
            RuntimeDirectoryMode = "0755";
            RuntimeDirectoryPreserve = "yes";
          };
        };

        oracle-opencti = {
          description = "Oracle OpenCTI threat-intelligence stack";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          requires = [
            "docker.service"
            "oracle-opencti-prepare.service"
          ];
          after = [
            "docker.service"
            "network-online.target"
            "oracle-opencti-prepare.service"
          ];
          restartTriggers = [ composeFile ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = stackStart;
            ExecStop = "-${stackStop}";
            Restart = "on-failure";
            RestartSec = "30s";
            TimeoutStartSec = "90min";
            TimeoutStopSec = "3min";
          };
        };

        oracle-opencti-health = {
          description = "Verify Oracle containers and trusted HTTPS API";
          requires = [ "oracle-opencti.service" ];
          after = [
            "nginx.service"
            "oracle-opencti.service"
          ];
          unitConfig.ConditionPathExists = secretsReadyMarker;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = healthCheck;
            TimeoutStartSec = "1min";
          };
        };
      };

      systemd.timers.oracle-opencti-health = {
        description = "Frequent Oracle OpenCTI health verification";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10m";
          OnUnitActiveSec = "5m";
          AccuracySec = "1m";
          Unit = "oracle-opencti-health.service";
        };
      };

      thorn.acme = {
        enable = true;
        domain = hostname;
        group = config.services.nginx.group;
        reloadServices = [ "nginx.service" ];
      };

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        virtualHosts.${hostname} = {
          serverName = hostname;
          forceSSL = true;
          useACMEHost = hostname;
          extraConfig = ''
            allow 127.0.0.1;
            allow ::1;
            allow 172.16.25.0/24;
            allow 192.168.1.0/24;
            allow 10.10.10.0/24;
            deny all;

            add_header Strict-Transport-Security "max-age=31536000" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header X-Frame-Options "SAMEORIGIN" always;
            add_header Referrer-Policy "same-origin" always;
            add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
            client_max_body_size 256m;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:8080";
            proxyWebsockets = true;
            extraConfig = ''
              if (!-f ${secretsReadyMarker}) {
                return 503;
              }
              proxy_buffering off;
              proxy_read_timeout 600s;
              proxy_send_timeout 600s;
            '';
          };
        };
      };
    };
}
