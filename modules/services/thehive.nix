{ inputs, ... }:
{
  nixos.modules.services-thehive =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "casebook.guildedthorn.arpa";
      stateDirectory = "/var/lib/casebook";
      configDirectory = "${stateDirectory}/config";
      secretsFile = "${stateDirectory}/secrets.env";
      adminPasswordFile = "${stateDirectory}/admin-initial-password";
      securedMarker = "${stateDirectory}/admin-secured";
      runtimeDirectory = "/run/casebook";
      runtimeSecuredMarker = "${runtimeDirectory}/admin-secured";
      lockFile = "/run/lock/casebook-thehive.lock";

      composeFile = pkgs.writeText "thornix-casebook-thehive-compose.yaml" (
        builtins.readFile ./casebook-compose.yaml
      );
      compose = "${pkgs.docker-compose}/bin/docker-compose --env-file ${secretsFile} --project-name thornix-casebook --file ${composeFile}";

      applicationConfig = pkgs.writeText "casebook-application.conf" ''
        include "/etc/thehive/secret.conf"

        db.janusgraph.storage {
          backend = cql
          hostname = ["cassandra"]
          cql {
            cluster-name = thp
            keyspace = thehive
            username = "cassandra"
            password = "cassandra"
          }
        }

        include "/etc/thehive/index.conf"

        storage {
          provider = localfs
          localfs.location = /opt/thp/thehive/files
        }

        application.baseUrl = "https://${hostname}"
        play.http.context = "/"
        play.http.parser.maxDiskBuffer = 1GB
        play.http.parser.maxMemoryBuffer = 256kB
        stream.longPolling.refresh = 45 seconds

        stream.get {
          maxAttempts = 5
          minBackoff = 100 milliseconds
          maxBackoff = 500 milliseconds
          randomFactor = 0.2
        }
      '';

      logbackConfig = pkgs.writeText "casebook-logback.xml" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <configuration debug="false">
          <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
              <pattern>%date [%level] %logger{36} [%X{kamonTraceId}] %message%n%xException{10}</pattern>
            </encoder>
          </appender>
          <logger name="org.thp.scalligraph.traversal" level="INFO"/>
          <logger name="org.janusgraph.graphdb.database.management.ManagementLogger" level="OFF"/>
          <logger name="org.apache.kafka" level="WARN"/>
          <root level="INFO">
            <appender-ref ref="STDOUT"/>
          </root>
        </configuration>
      '';

      composeCheckEnvironment = pkgs.writeText "casebook-compose-check.env" ''
        ELASTICSEARCH_PASSWORD=compose-check-only
      '';
      composeCheck =
        pkgs.runCommand "casebook-thehive-compose-check" { nativeBuildInputs = [ pkgs.docker-compose ]; }
          ''
            export HOME="$TMPDIR"
            docker-compose --env-file ${composeCheckEnvironment} \
              --project-name thornix-casebook --file ${composeFile} config --quiet
            touch "$out"
          '';

      prepare = pkgs.writeShellScript "casebook-thehive-prepare" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        ${pkgs.coreutils}/bin/install -d -m 0755 ${lib.escapeShellArg configDirectory}

        if [[ ! -s ${lib.escapeShellArg secretsFile} ]]; then
          temporary_secrets=$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${stateDirectory}/.secrets.env.XXXXXX"})
          trap '${pkgs.coreutils}/bin/rm -f -- "$temporary_secrets"' EXIT

          elasticsearch_password=$(${lib.getExe pkgs.openssl} rand -hex 32)
          thehive_app_secret=$(${lib.getExe pkgs.openssl} rand -hex 32)
          {
            printf 'ELASTICSEARCH_PASSWORD=%s\n' "$elasticsearch_password"
            printf 'THEHIVE_APP_SECRET=%s\n' "$thehive_app_secret"
          } > "$temporary_secrets"
          ${pkgs.coreutils}/bin/chmod 0600 "$temporary_secrets"
          ${pkgs.coreutils}/bin/mv -- "$temporary_secrets" ${lib.escapeShellArg secretsFile}
          trap - EXIT
        fi

        # shellcheck disable=SC1090
        source ${lib.escapeShellArg secretsFile}
        : "''${ELASTICSEARCH_PASSWORD:?missing ELASTICSEARCH_PASSWORD}"
        : "''${THEHIVE_APP_SECRET:?missing THEHIVE_APP_SECRET}"

        ${pkgs.coreutils}/bin/install -m 0444 ${applicationConfig} ${lib.escapeShellArg "${configDirectory}/application.conf"}
        ${pkgs.coreutils}/bin/install -m 0444 ${logbackConfig} ${lib.escapeShellArg "${configDirectory}/logback.xml"}

        temporary_index=$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${configDirectory}/.index.conf.XXXXXX"})
        temporary_secret=$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${configDirectory}/.secret.conf.XXXXXX"})
        trap '${pkgs.coreutils}/bin/rm -f -- "$temporary_index" "$temporary_secret"' EXIT

        printf '%s\n' \
          'db.janusgraph.index.search {' \
          '  backend = elasticsearch' \
          '  hostname = ["elasticsearch"]' \
          '  index-name = thehive' \
          '  elasticsearch.http.auth {' \
          '    type = "basic"' \
          '    basic {' \
          '      username = "elastic"' \
          "      password = \"$ELASTICSEARCH_PASSWORD\"" \
          '    }' \
          '  }' \
          '}' > "$temporary_index"
        printf 'play.http.secret.key="%s"\n' "$THEHIVE_APP_SECRET" > "$temporary_secret"

        ${pkgs.coreutils}/bin/chmod 0444 "$temporary_index" "$temporary_secret"
        ${pkgs.coreutils}/bin/mv -- "$temporary_index" ${lib.escapeShellArg "${configDirectory}/index.conf"}
        ${pkgs.coreutils}/bin/mv -- "$temporary_secret" ${lib.escapeShellArg "${configDirectory}/secret.conf"}
        trap - EXIT
      '';

      stackStart = pkgs.writeShellScript "casebook-thehive-start" ''
        set -o errexit -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 1800 9
        exec ${compose} up --detach --remove-orphans
      '';

      stackStop = pkgs.writeShellScript "casebook-thehive-stop" ''
        set -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 60 9 || exit 0
        exec ${compose} stop --timeout 60
      '';

      adminBootstrap = pkgs.writeShellScript "casebook-thehive-admin-bootstrap" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        if [[ -e ${lib.escapeShellArg securedMarker} ]]; then
          ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg runtimeSecuredMarker}
          ${pkgs.coreutils}/bin/chmod 0444 ${lib.escapeShellArg runtimeSecuredMarker}
          exit 0
        fi

        pending_password=${lib.escapeShellArg "${stateDirectory}/.admin-password.pending"}
        if [[ ! -s "$pending_password" ]]; then
          ${lib.getExe pkgs.openssl} rand -base64 36 | \
            ${pkgs.coreutils}/bin/tr -d '\n' > "$pending_password"
          printf '\n' >> "$pending_password"
          ${pkgs.coreutils}/bin/chmod 0600 "$pending_password"
        fi
        password=$(${pkgs.coreutils}/bin/tr -d '\n' < "$pending_password")
        cookie_file=${lib.escapeShellArg "${runtimeDirectory}/admin.cookie"}

        login_with_password() {
          candidate=$1
          payload=$(${lib.getExe pkgs.jq} -cn \
            --arg user 'admin@thehive.local' \
            --arg password "$candidate" \
            '{user: $user, password: $password}')
          ${pkgs.curl}/bin/curl --fail --silent --show-error \
            --connect-timeout 3 --max-time 20 \
            --cookie-jar "$cookie_file" \
            --header 'Content-Type: application/json' \
            --data "$payload" \
            http://127.0.0.1:9000/api/v1/login
        }

        for ((attempt = 1; attempt <= 180; attempt++)); do
          current_password=""
          login_response=""

          if login_response=$(login_with_password secret 2>/dev/null); then
            current_password=secret
          elif login_response=$(login_with_password "$password" 2>/dev/null); then
            # A crash after TheHive committed the password but before the
            # local marker was written is safe and recoverable.
            current_password=$password
          fi

          if [[ -n "$current_password" ]]; then
            user_id=$(printf '%s' "$login_response" | ${lib.getExe pkgs.jq} -er '._id')

            if [[ "$current_password" == secret ]]; then
              encoded_user_id=$(printf '%s' "$user_id" | ${lib.getExe pkgs.jq} -sRr @uri)
              change_payload=$(${lib.getExe pkgs.jq} -cn \
                --arg currentPassword secret \
                --arg password "$password" \
                '{currentPassword: $currentPassword, password: $password}')
              ${pkgs.curl}/bin/curl --fail --silent --show-error \
                --connect-timeout 3 --max-time 20 \
                --cookie "$cookie_file" \
                --header 'Content-Type: application/json' \
                --request POST --data "$change_payload" \
                "http://127.0.0.1:9000/api/v1/user/$encoded_user_id/password/change"
            fi

            ${pkgs.coreutils}/bin/install -m 0600 "$pending_password" ${lib.escapeShellArg adminPasswordFile}
            ${pkgs.coreutils}/bin/rm -f -- "$pending_password" "$cookie_file"
            ${pkgs.coreutils}/bin/touch \
              ${lib.escapeShellArg securedMarker} \
              ${lib.escapeShellArg runtimeSecuredMarker}
            ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg securedMarker}
            ${pkgs.coreutils}/bin/chmod 0444 ${lib.escapeShellArg runtimeSecuredMarker}
            exit 0
          fi

          if ((attempt % 6 == 0)); then
            echo "Still waiting to secure TheHive administrator ($attempt/180)"
          fi
          sleep 10
        done

        echo "error: TheHive administrator bootstrap did not finish within 30 minutes" >&2
        ${compose} ps >&2 || true
        exit 1
      '';

      healthCheck = pkgs.writeShellScript "casebook-thehive-health" ''
        set -o errexit -o nounset -o pipefail

        check_casebook() {
          for service in cassandra elasticsearch thehive; do
            container_id=$(${compose} ps --quiet --status running "$service")
            [[ -n "$container_id" ]] || return 1
          done

          ${pkgs.curl}/bin/curl --fail --silent --location \
            --connect-timeout 3 --max-time 20 --output /dev/null \
            --cacert ${inputs.self}/certs/ThornCloud_CA.crt \
            --resolve ${hostname}:443:127.0.0.1 \
            https://${hostname}/
        }

        for ((attempt = 1; attempt <= 30; attempt++)); do
          if check_casebook; then
            exit 0
          fi
          if ((attempt == 30)); then
            echo "error: Casebook did not become healthy within five minutes" >&2
            ${compose} ps >&2 || true
            exit 1
          fi
          sleep 10
        done
      '';

      composeCommand = pkgs.writeShellApplication {
        name = "casebook-compose";
        runtimeInputs = [ pkgs.docker-compose ];
        text = ''
          if ((EUID != 0)); then
            echo "error: casebook-compose must run as root" >&2
            exit 1
          fi
          exec ${compose} "$@"
        '';
      };

      adminPasswordCommand = pkgs.writeShellApplication {
        name = "casebook-admin-password";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if ((EUID != 0)); then
            echo "error: casebook-admin-password must run as root" >&2
            exit 1
          fi
          if [[ ! -s ${lib.escapeShellArg adminPasswordFile} ]]; then
            echo "error: Casebook has not finished securing its administrator" >&2
            exit 1
          fi

          printf 'Username: admin@thehive.local\nPassword: '
          cat ${lib.escapeShellArg adminPasswordFile}
          echo "Change this generated bootstrap password after first login; this local copy will then be stale."
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "casebook";
          message = "services-thehive is a fixed service profile for the casebook host";
        }
        {
          assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          message = "Casebook's reviewed container image digests are pinned for linux/amd64";
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

      environment.systemPackages = [
        adminPasswordCommand
        composeCommand
      ];

      systemd.services = {
        casebook-thehive-prepare = {
          description = "Generate Casebook runtime secrets and TheHive configuration";
          wantedBy = [ "multi-user.target" ];
          before = [ "casebook-thehive.service" ];
          restartTriggers = [
            applicationConfig
            logbackConfig
            prepare
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = prepare;
            StateDirectory = "casebook";
            StateDirectoryMode = "0700";
          };
        };

        casebook-thehive = {
          description = "Casebook TheHive incident-response stack";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          requires = [
            "casebook-thehive-prepare.service"
            "docker.service"
          ];
          after = [
            "casebook-thehive-prepare.service"
            "docker.service"
            "network-online.target"
          ];
          restartTriggers = [ composeFile ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = stackStart;
            ExecStop = "-${stackStop}";
            Restart = "on-failure";
            RestartSec = "30s";
            TimeoutStartSec = "45min";
            TimeoutStopSec = "2min";
          };
        };

        casebook-thehive-admin = {
          description = "Replace TheHive's default administrator credential";
          wantedBy = [ "multi-user.target" ];
          requires = [ "casebook-thehive.service" ];
          after = [ "casebook-thehive.service" ];
          before = [ "nginx.service" ];
          restartTriggers = [ adminBootstrap ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = adminBootstrap;
            StateDirectory = "casebook";
            StateDirectoryMode = "0700";
            RuntimeDirectory = "casebook";
            RuntimeDirectoryMode = "0755";
            RuntimeDirectoryPreserve = "yes";
            TimeoutStartSec = "35min";
          };
        };

        casebook-thehive-health = {
          description = "Verify Casebook containers and trusted HTTPS UI";
          requires = [ "casebook-thehive.service" ];
          after = [
            "casebook-thehive-admin.service"
            "casebook-thehive.service"
            "nginx.service"
          ];
          unitConfig.ConditionPathExists = securedMarker;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = healthCheck;
            TimeoutStartSec = "6min";
          };
        };

        nginx = {
          wants = [ "casebook-thehive-admin.service" ];
          after = [ "casebook-thehive-admin.service" ];
        };
      };

      systemd.timers.casebook-thehive-health = {
        description = "Frequent Casebook TheHive health verification";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
          AccuracySec = "1m";
          Unit = "casebook-thehive-health.service";
        };
      };

      thorn.backup = {
        enable = true;
        schedule = "*-*-* 05:00:00";
        paths = [
          stateDirectory
          "/var/lib/docker/volumes"
        ];
        quiesceServices = [ "casebook-thehive.service" ];
        cleanupCommand = ''
          ${pkgs.systemd}/bin/systemctl start casebook-thehive-health.service
        '';
        restorePaths = [ secretsFile ];
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
            client_max_body_size 1g;
          '';
          locations."/" = {
            proxyPass = "http://127.0.0.1:9000";
            proxyWebsockets = true;
            extraConfig = ''
              if (!-f ${runtimeSecuredMarker}) {
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
