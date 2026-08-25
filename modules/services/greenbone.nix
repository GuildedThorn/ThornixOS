{ inputs, ... }:
{
  nixos.modules.services-greenbone =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "sieve.guildedthorn.arpa";
      # Give Compose its own content-addressed store path. Referring directly
      # into inputs.self would change the path on every repository commit and
      # unnecessarily restart the scanner even when this file was untouched.
      composeFile = pkgs.writeText "thornix-sieve-greenbone-compose.yaml" (
        builtins.readFile ./greenbone-compose.yaml
      );
      compose = "${pkgs.docker-compose}/bin/docker-compose --project-name thornix-sieve --file ${composeFile}";
      lockFile = "/run/lock/sieve-greenbone.lock";
      stateDirectory = "/var/lib/sieve";
      runtimeDirectory = "/run/sieve";
      adminPasswordFile = "${stateDirectory}/admin-initial-password";
      securedMarker = "${stateDirectory}/admin-secured";
      runtimeSecuredMarker = "${runtimeDirectory}/admin-secured";

      feedServices = [
        "vulnerability-tests"
        "notus-data"
        "scap-data"
        "cert-bund-data"
        "dfn-cert-data"
        "data-objects"
        "report-formats"
        "gpg-data"
      ];
      feedServiceArguments = lib.concatStringsSep " " feedServices;

      composeCheck =
        pkgs.runCommand "sieve-greenbone-compose-check"
          {
            nativeBuildInputs = [ pkgs.docker-compose ];
          }
          ''
            export HOME="$TMPDIR"
            docker-compose --project-name thornix-sieve --file ${composeFile} config --quiet
            touch "$out"
          '';

      stackStart = pkgs.writeShellScript "sieve-greenbone-start" ''
        set -o errexit -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 1800 9
        exec ${compose} up --detach --remove-orphans
      '';

      stackStop = pkgs.writeShellScript "sieve-greenbone-stop" ''
        set -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 60 9 || exit 0
        exec ${compose} stop --timeout 60
      '';

      feedUpdate = pkgs.writeShellScript "sieve-greenbone-feed-update" ''
        set -o errexit -o nounset -o pipefail
        exec 9>${lockFile}
        ${pkgs.util-linux}/bin/flock --wait 1800 9

        # Feed images change daily and the VT/SCAP generations are roughly
        # 3 GiB each. A weekly prune is too infrequent for Sieve's disk: old
        # generations can exhaust overlayfs before the next update completes.
        # A plain image prune removes dangling layers only; it never removes
        # running images or the named volumes holding feeds and database data.
        prune_dangling_images() {
          ${pkgs.docker}/bin/docker image prune --force
        }
        trap 'prune_dangling_images || true' EXIT
        prune_dangling_images

        # Only Greenbone's data containers roll automatically. Executable
        # services remain on the reviewed amd64 digests in composeFile.
        # The Community registry occasionally times out one manifest HEAD.
        # Pull feeds independently so successful downloads are retained, and
        # retry only the failed service rather than aborting all eight pulls.
        for service in ${feedServiceArguments}; do
          for attempt in 1 2 3; do
            if ${compose} pull --quiet "$service"; then
              break
            fi
            if [[ "$attempt" == 3 ]]; then
              echo "error: failed to pull Greenbone feed image: $service" >&2
              exit 1
            fi
            echo "warning: retrying Greenbone feed image $service ($attempt/3)" >&2
            sleep $((attempt * 30))
          done
        done
        # Recreate only the rolling feed writers. A full-stack `up` also
        # resolves pinned application/helper images even though this job does
        # not update them; Greenbone may retire those old registry manifests.
        # Application rollouts remain the responsibility of sieve-greenbone.
        ${compose} up --detach --remove-orphans ${feedServiceArguments}
      '';

      healthCheck = pkgs.writeShellScript "sieve-greenbone-health" ''
        set -o errexit -o nounset -o pipefail

        for service in redis-server pg-gvm gvmd gsad nginx openvas openvasd ospd-openvas; do
          container_id=$(${compose} ps --quiet --status running "$service")
          if [[ -z "$container_id" ]]; then
            echo "error: critical Greenbone container is not running: $service" >&2
            exit 1
          fi
        done

        ${pkgs.curl}/bin/curl \
          --fail --silent --show-error --insecure \
          --connect-timeout 3 --max-time 15 \
          --output /dev/null \
          https://127.0.0.1:9443/
      '';

      adminBootstrap = pkgs.writeShellScript "sieve-greenbone-admin-bootstrap" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        if [[ -e ${lib.escapeShellArg securedMarker} ]]; then
          ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg runtimeSecuredMarker}
          ${pkgs.coreutils}/bin/chmod 0444 ${lib.escapeShellArg runtimeSecuredMarker}
          exit 0
        fi

        pending_password=${lib.escapeShellArg "${stateDirectory}/.admin-password.pending"}
        if [[ ! -s "$pending_password" ]]; then
          ${pkgs.openssl}/bin/openssl rand -base64 36 | \
            ${pkgs.coreutils}/bin/tr -d '\n' > "$pending_password"
          printf '\n' >> "$pending_password"
        fi
        password=$(${pkgs.coreutils}/bin/tr -d '\n' < "$pending_password")

        # The upstream containers initially create admin/admin. Port 9443 is
        # loopback-only and the outer nginx returns 503 until this marker is
        # present, so that credential is never remotely usable.
        for ((attempt = 1; attempt <= 180; attempt++)); do
          if ${compose} exec -T -u gvmd gvmd \
            gvmd --user=admin --new-password="$password" >/dev/null 2>&1; then
            ${pkgs.coreutils}/bin/install -m 0600 \
              "$pending_password" ${lib.escapeShellArg adminPasswordFile}
            ${pkgs.coreutils}/bin/rm -f "$pending_password"
            ${pkgs.coreutils}/bin/touch \
              ${lib.escapeShellArg securedMarker} \
              ${lib.escapeShellArg runtimeSecuredMarker}
            ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg securedMarker}
            ${pkgs.coreutils}/bin/chmod 0444 ${lib.escapeShellArg runtimeSecuredMarker}
            exit 0
          fi

          if ((attempt % 6 == 0)); then
            echo "Still waiting for gvmd administrator bootstrap ($attempt/180)"
          fi
          sleep 10
        done

        echo "error: gvmd did not accept the secured administrator password within 30 minutes" >&2
        ${compose} ps >&2 || true
        exit 1
      '';

      composeCommand = pkgs.writeShellApplication {
        name = "sieve-compose";
        runtimeInputs = [ pkgs.docker-compose ];
        text = ''
          if ((EUID != 0)); then
            echo "error: sieve-compose must run as root" >&2
            exit 1
          fi
          exec ${compose} "$@"
        '';
      };

      adminPasswordCommand = pkgs.writeShellApplication {
        name = "sieve-admin-password";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if ((EUID != 0)); then
            echo "error: sieve-admin-password must run as root" >&2
            exit 1
          fi
          if [[ ! -s ${lib.escapeShellArg adminPasswordFile} ]]; then
            echo "error: Sieve has not finished securing its administrator account" >&2
            exit 1
          fi

          printf 'Username: admin\nPassword: '
          cat ${lib.escapeShellArg adminPasswordFile}
          echo "Change this password in GSA after the first login; this file is only the generated bootstrap credential."
        '';
      };

      feedUpdateCommand = pkgs.writeShellApplication {
        name = "sieve-update-feeds";
        runtimeInputs = [ pkgs.systemd ];
        text = ''
          if ((EUID != 0)); then
            echo "error: sieve-update-feeds must run as root" >&2
            exit 1
          fi
          exec systemctl start sieve-greenbone-feed-update.service
        '';
      };

      scopeCommand = pkgs.writeShellApplication {
        name = "sieve-authorized-scope";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          exec cat /etc/sieve/authorized-scan-scope.txt
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "sieve";
          message = "services-greenbone is a fixed service profile for the sieve host";
        }
        {
          assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          message = "Sieve's reviewed Greenbone image digests are pinned for linux/amd64";
        }
      ];

      system.checks = [ composeCheck ];

      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
        # Feed refreshes replace rolling data images. Reclaim superseded
        # layers after they are no longer referenced, but never prune volumes
        # containing Greenbone's feeds or PostgreSQL state.
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [ "--all" ];
        };
        daemon.settings = {
          "live-restore" = true;
          "log-driver" = "journald";
          "userland-proxy" = false;
        };
      };

      environment = {
        systemPackages = [
          adminPasswordCommand
          composeCommand
          feedUpdateCommand
          scopeCommand
        ];

        # This documents the authorization boundary; no scan starts merely
        # because the VM deploys. Create targets/tasks deliberately in GSA.
        etc."sieve/authorized-scan-scope.txt".text = ''
          # ThornCloud networks authorized for owner-initiated assessment
          172.16.25.0/24
          192.168.1.0/24

          # Never add WAN/public ranges here without separate authorization.
        '';
      };

      systemd.services = {
        sieve-greenbone = {
          description = "Sieve Greenbone Community Edition stack";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          requires = [ "docker.service" ];
          after = [
            "docker.service"
            "network-online.target"
          ];
          unitConfig = {
            StartLimitBurst = 3;
            StartLimitIntervalSec = "20min";
          };
          restartTriggers = [ composeFile ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = stackStart;
            ExecStop = "-${stackStop}";
            Restart = "on-failure";
            RestartSec = "30s";
            TimeoutStartSec = "45min";
            # Compose may wait up to 60 seconds for several database/scanner
            # containers. Two minutes cut a clean stop short in production
            # and left data containers killed with status 137.
            TimeoutStopSec = "5min";
          };
        };

        sieve-greenbone-admin = {
          description = "Replace Greenbone's default administrator credential";
          wantedBy = [ "multi-user.target" ];
          requires = [ "sieve-greenbone.service" ];
          after = [ "sieve-greenbone.service" ];
          before = [ "nginx.service" ];
          restartTriggers = [ adminBootstrap ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = adminBootstrap;
            StateDirectory = "sieve";
            StateDirectoryMode = "0700";
            RuntimeDirectory = "sieve";
            RuntimeDirectoryMode = "0755";
            TimeoutStartSec = "35min";
          };
        };

        sieve-greenbone-feed-update = {
          description = "Refresh Sieve Greenbone Community Feed images";
          wants = [ "network-online.target" ];
          requires = [ "sieve-greenbone.service" ];
          after = [
            "network-online.target"
            "sieve-greenbone.service"
          ];
          unitConfig = {
            ConditionPathExists = securedMarker;
            # A registry outage should retry during the same maintenance
            # window instead of leaving stale feeds until the next day.
            StartLimitBurst = 4;
            StartLimitIntervalSec = "2h";
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = feedUpdate;
            Restart = "on-failure";
            RestartSec = "15min";
            TimeoutStartSec = "60min";
          };
        };

        sieve-greenbone-health = {
          description = "Verify Sieve Greenbone critical containers and UI";
          requires = [ "sieve-greenbone.service" ];
          after = [
            "sieve-greenbone-admin.service"
            "sieve-greenbone.service"
          ];
          unitConfig.ConditionPathExists = securedMarker;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = healthCheck;
            TimeoutStartSec = "1min";
          };
        };

        # Normal ordering prevents the UI from racing the password bootstrap.
        # The nginx file guard below remains the fail-closed boundary if the
        # bootstrap unit itself errors.
        nginx = {
          wants = [ "sieve-greenbone-admin.service" ];
          after = [ "sieve-greenbone-admin.service" ];
        };
      };

      systemd.timers.sieve-greenbone-feed-update = {
        description = "Daily Sieve Greenbone Community Feed refresh";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 03:15:00";
          RandomizedDelaySec = "1h";
          Persistent = true;
          Unit = "sieve-greenbone-feed-update.service";
        };
      };

      systemd.timers.sieve-greenbone-health = {
        description = "Frequent Sieve Greenbone health verification";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
          AccuracySec = "1m";
          Unit = "sieve-greenbone-health.service";
        };
      };

      # Anvil owns the user-facing certificate. Greenbone's generated TLS is
      # retained only for the loopback proxy hop and is never network-visible.
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
            add_header Strict-Transport-Security "max-age=31536000" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "same-origin" always;
            add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
          '';
          locations."/" = {
            proxyPass = "https://127.0.0.1:9443";
            proxyWebsockets = true;
            extraConfig = ''
              if (!-f ${runtimeSecuredMarker}) {
                return 503;
              }

              # This is Greenbone's generated self-signed certificate on a
              # loopback-only socket. User-facing TLS is verified at Anvil's
              # certificate above; no untrusted network hop exists here.
              proxy_ssl_verify off;
              proxy_ssl_server_name on;
              proxy_ssl_name ${hostname};
              proxy_read_timeout 600s;
              proxy_send_timeout 600s;
            '';
          };
        };
      };
    };
}
