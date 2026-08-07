{ ... }:
{
  nixos.modules.services-opencanary =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      composeFile = pkgs.writeText "thornix-lure-opencanary-compose.yaml" (
        builtins.readFile ./lure-compose.yaml
      );
      compose = "${pkgs.docker-compose}/bin/docker-compose --project-name thornix-lure --file ${composeFile}";
      stateDirectory = "/var/lib/lure";
      tlsDirectory = "${stateDirectory}/tls";
      lockFile = "/run/lock/lure-opencanary.lock";

      configFile = pkgs.writeText "thornix-lure-opencanary.conf" (
        builtins.toJSON {
          "device.node_id" = "nas01";
          "ip.ignorelist" = [
            "127.0.0.1"
            # Sieve's authorized vulnerability scans are expected activity,
            # not a high-confidence lateral-movement signal.
            "172.16.25.56"
          ];
          "logtype.ignorelist" = [ ];

          "git.enabled" = true;
          "git.port" = 9418;

          "ftp.enabled" = true;
          "ftp.port" = 21;
          "ftp.banner" = "220 NAS01 FTP server ready";
          "ftp.log_auth_attempt_initiated" = true;

          "http.enabled" = true;
          "http.port" = 80;
          "http.banner" = "Apache/2.2.22 (Ubuntu)";
          "http.skin" = "nasLogin";
          "http.log_unimplemented_method_requests" = true;
          "http.log_redirect_request" = true;

          "https.enabled" = true;
          "https.port" = 443;
          "https.skin" = "nasLogin";
          "https.certificate" = "/tls/certificate.pem";
          "https.key" = "/tls/key.pem";

          "httpproxy.enabled" = true;
          "httpproxy.port" = 8080;
          "httpproxy.skin" = "squid";

          "llmnr.enabled" = false;
          "llmnr.query_interval" = 60;
          "llmnr.query_splay" = 5;
          "llmnr.hostname" = "NAS01";
          "llmnr.port" = 5355;

          logger = {
            class = "PyLogger";
            kwargs = {
              formatters.plain.format = "%(message)s";
              handlers.console = {
                class = "logging.StreamHandler";
                stream = "ext://sys.stdout";
              };
            };
          };

          "portscan.enabled" = false;
          "portscan.ignore_localhost" = true;
          "portscan.logfile" = "/var/log/kern.log";
          "portscan.synrate" = 5;
          "portscan.nmaposrate" = 5;
          "portscan.lorate" = 3;
          "portscan.ignore_ports" = [ ];

          "smb.enabled" = false;
          "smb.auditfile" = "/var/log/samba-audit.log";

          "mysql.enabled" = true;
          "mysql.port" = 3306;
          "mysql.banner" = "5.5.43-0ubuntu0.14.04.1";
          "mysql.log_connection_made" = true;

          # Real OpenSSH remains on 22 but is source-limited to three admin
          # machines. The decoy SSH service uses a common alternate port.
          "ssh.enabled" = true;
          "ssh.port" = 2222;
          "ssh.version" = "SSH-2.0-OpenSSH_5.1p1 Debian-4";

          "redis.enabled" = true;
          "redis.port" = 6379;
          "rdp.enabled" = true;
          "rdp.port" = 3389;
          "sip.enabled" = true;
          "sip.port" = 5060;
          "snmp.enabled" = false;
          "snmp.port" = 161;
          "ntp.enabled" = true;
          "ntp.port" = 123;
          "tftp.enabled" = true;
          "tftp.port" = 69;

          "tcpbanner.enabled" = false;
          "tcpbanner.maxnum" = 10;
          "tcpbanner_1.enabled" = false;
          "tcpbanner_1.port" = 8001;
          "tcpbanner_1.datareceivedbanner" = "";
          "tcpbanner_1.initbanner" = "";
          "tcpbanner_1.alertstring.enabled" = false;
          "tcpbanner_1.alertstring" = "";
          "tcpbanner_1.keep_alive.enabled" = false;
          "tcpbanner_1.keep_alive_secret" = "";
          "tcpbanner_1.keep_alive_probes" = 11;
          "tcpbanner_1.keep_alive_interval" = 300;
          "tcpbanner_1.keep_alive_idle" = 300;

          "telnet.enabled" = true;
          "telnet.port" = 23;
          "telnet.banner" = "NAS01 login: ";
          "telnet.honeycreds" = [
            {
              username = "admin";
              password = "admin1";
            }
          ];
          "telnet.log_tcp_connection" = true;

          "mssql.enabled" = true;
          "mssql.version" = "2012";
          "mssql.port" = 1433;
          "vnc.enabled" = true;
          "vnc.port" = 5900;
          "mongodb.enabled" = true;
          "mongodb.port" = 27017;
          "mongodb.version" = "4.4.6";
        }
      );

      composeCheck =
        pkgs.runCommand "lure-opencanary-compose-check" { nativeBuildInputs = [ pkgs.docker-compose ]; }
          ''
            export HOME="$TMPDIR"
            docker-compose --project-name thornix-lure --file ${composeFile} config --quiet
            touch "$out"
          '';

      prepare = pkgs.writeShellScript "lure-opencanary-prepare" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        ${pkgs.coreutils}/bin/install -d -m 0755 ${lib.escapeShellArg tlsDirectory}
        if [[ ! -s ${lib.escapeShellArg "${tlsDirectory}/certificate.pem"} || ! -s ${lib.escapeShellArg "${tlsDirectory}/key.pem"} ]]; then
          temporary_directory=$(${pkgs.coreutils}/bin/mktemp -d ${lib.escapeShellArg "${stateDirectory}/.tls.XXXXXX"})
          trap '${pkgs.coreutils}/bin/rm -rf -- "$temporary_directory"' EXIT

          ${lib.getExe pkgs.openssl} req -x509 -newkey rsa:2048 -nodes \
            -days 3650 -sha256 \
            -subj "/CN=nas01.guildedthorn.arpa" \
            -addext "subjectAltName=DNS:nas01.guildedthorn.arpa,IP:172.16.25.58" \
            -keyout "$temporary_directory/key.pem" \
            -out "$temporary_directory/certificate.pem"

          ${pkgs.coreutils}/bin/install -m 0444 "$temporary_directory/certificate.pem" ${lib.escapeShellArg "${tlsDirectory}/certificate.pem"}
          ${pkgs.coreutils}/bin/install -m 0444 "$temporary_directory/key.pem" ${lib.escapeShellArg "${tlsDirectory}/key.pem"}
          trap - EXIT
          ${pkgs.coreutils}/bin/rm -rf -- "$temporary_directory"
        fi
      '';

      stackStart = pkgs.writeShellScript "lure-opencanary-start" ''
        set -o errexit -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 300 9
        ${compose} up --detach --remove-orphans

        # `docker compose up -d` only proves that a container was created.
        # Keep the systemd unit in activating state until the actual decoy
        # listener answers; the loopback request is excluded by OpenCanary.
        for ((attempt = 1; attempt <= 90; attempt++)); do
          container_id=$(${compose} ps --quiet --status running opencanary)
          if [[ -n "$container_id" ]] && \
            ${pkgs.curl}/bin/curl --fail --silent --show-error \
              --connect-timeout 2 --max-time 5 --output /dev/null \
              http://127.0.0.1/; then
            exit 0
          fi
          sleep 2
        done

        echo "error: OpenCanary did not expose its decoy HTTP listener within three minutes" >&2
        ${compose} ps >&2 || true
        exit 1
      '';

      stackStop = pkgs.writeShellScript "lure-opencanary-stop" ''
        set -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 60 9 || exit 0
        exec ${compose} stop --timeout 30
      '';

      healthCheck = pkgs.writeShellScript "lure-opencanary-health" ''
        set -o errexit -o nounset -o pipefail
        container_id=$(${compose} ps --quiet --status running opencanary)
        if [[ -z "$container_id" ]]; then
          echo "error: OpenCanary container is not running" >&2
          exit 1
        fi

        ${pkgs.curl}/bin/curl --fail --silent --show-error \
          --connect-timeout 3 --max-time 10 --output /dev/null \
          http://127.0.0.1/
      '';

      composeCommand = pkgs.writeShellApplication {
        name = "lure-compose";
        runtimeInputs = [ pkgs.docker-compose ];
        text = ''
          if ((EUID != 0)); then
            echo "error: lure-compose must run as root" >&2
            exit 1
          fi
          exec ${compose} "$@"
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "lure";
          message = "services-opencanary is a fixed service profile for the lure host";
        }
        {
          assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          message = "Lure's reviewed OpenCanary image digest is pinned for linux/amd64";
        }
      ];

      system.checks = [ composeCheck ];

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
        systemPackages = [ composeCommand ];
        etc."lure/opencanary.conf".source = configFile;
      };

      systemd.services = {
        lure-opencanary-prepare = {
          description = "Create Lure's deceptive HTTPS identity";
          wantedBy = [ "multi-user.target" ];
          before = [ "lure-opencanary.service" ];
          restartTriggers = [ prepare ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = prepare;
            StateDirectory = "lure";
            StateDirectoryMode = "0700";
          };
        };

        lure-opencanary = {
          description = "Lure OpenCanary deception sensor";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          requires = [
            "docker.service"
            "lure-opencanary-prepare.service"
          ];
          after = [
            "docker.service"
            "lure-opencanary-prepare.service"
            "network-online.target"
          ];
          restartTriggers = [
            composeFile
            configFile
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = stackStart;
            ExecStop = "-${stackStop}";
            Restart = "on-failure";
            RestartSec = "15s";
            TimeoutStartSec = "15min";
            TimeoutStopSec = "1min";
          };
        };

        lure-opencanary-health = {
          description = "Verify Lure OpenCanary container and decoy HTTP";
          requires = [ "lure-opencanary.service" ];
          after = [ "lure-opencanary.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = healthCheck;
            TimeoutStartSec = "30s";
          };
        };
      };

      systemd.timers.lure-opencanary-health = {
        description = "Frequent Lure OpenCanary health verification";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "3m";
          OnUnitActiveSec = "5m";
          AccuracySec = "1m";
          Unit = "lure-opencanary-health.service";
        };
      };
    };
}
