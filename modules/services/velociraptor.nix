{ inputs, ... }:
{
  nixos.modules.services-velociraptor =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "hound.guildedthorn.arpa";
      stateDirectory = "/var/lib/velociraptor";
      configFile = "${stateDirectory}/server.config.yaml";
      datastoreDirectory = "${stateDirectory}/datastore";
      adminPasswordFile = "${stateDirectory}/admin-initial-password";
      adminMarker = "${stateDirectory}/admin-created";
      runtimeReadyMarker = "/run/hound/admin-created";

      # nixpkgs does not currently package Velociraptor. Use the official
      # static release directly, pinned by the SHA-256 published with v0.77.1.
      # The static binary keeps Hound native to systemd without introducing a
      # privileged container daemon solely for this service.
      velociraptor = pkgs.stdenvNoCC.mkDerivation {
        pname = "velociraptor";
        version = "0.77.1";

        src = pkgs.fetchurl {
          url = "https://github.com/Velocidex/velociraptor/releases/download/v0.77.1/velociraptor-v0.77.1-linux-amd64-musl";
          hash = "sha256-w54NQCd2VV01yVVd9B1ZAb+38y9Lq6HQZ5XRKGICik8=";
        };

        dontUnpack = true;
        installPhase = ''
          runHook preInstall
          install -Dm0555 "$src" "$out/bin/velociraptor"
          runHook postInstall
        '';

        meta = {
          description = "Endpoint visibility and digital forensic collection platform";
          homepage = "https://docs.velociraptor.app/";
          license = lib.licenses.agpl3Only;
          mainProgram = "velociraptor";
          platforms = [ "x86_64-linux" ];
        };
      };

      # This file contains policy only. `config generate` adds the internal CA,
      # frontend and gateway private keys at first boot directly into mutable
      # service state; none of that cryptographic material enters the Nix
      # store. On later activations `config show --merge_file` reapplies this
      # declarative policy while preserving all generated keys and trust.
      configMerge = pkgs.writeText "hound-velociraptor-config-merge.json" (
        builtins.toJSON {
          Client.server_urls = [ "https://${hostname}:8000/" ];

          Datastore = {
            implementation = "FileBaseDataStore";
            location = datastoreDirectory;
            filestore_directory = datastoreDirectory;
            compression = "zlib";
          };

          Frontend = {
            inherit hostname;
            bind_address = "0.0.0.0";
            bind_port = 8000;
            run_as_user = "velociraptor";
            concurrency = 10;
            resources = {
              expected_clients = 100;
              connections_per_second = 25;
              notifications_per_second = 10;
              max_upload_size = 104857600;
            };
          };

          GUI = {
            bind_address = "127.0.0.1";
            bind_port = 8889;
            public_url = "https://${hostname}/app/index.html";
            allowed_cidr = [ "127.0.0.0/8" ];
            authenticator.type = "Basic";
          };

          Monitoring = {
            bind_address = "0.0.0.0";
            bind_port = 8003;
          };
        }
      );

      bootstrap = pkgs.writeShellScript "hound-velociraptor-bootstrap" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg datastoreDirectory}

        if [[ -e ${lib.escapeShellArg configFile} && ! -f ${lib.escapeShellArg configFile} ]]; then
          echo "error: Velociraptor configuration is not a regular file" >&2
          exit 1
        fi

        temporary_config=$(${pkgs.coreutils}/bin/mktemp \
          ${lib.escapeShellArg "${stateDirectory}/.server.config.yaml.XXXXXX"})
        reissued_config="$temporary_config.reissued"
        trap '${pkgs.coreutils}/bin/rm -f -- "$temporary_config" "$reissued_config"' EXIT

        if [[ ! -s ${lib.escapeShellArg configFile} ]]; then
          ${lib.getExe velociraptor} config generate \
            --merge_file ${configMerge} > "$temporary_config"

          # The generated CA is valid for ten years but the default frontend
          # and gateway certificates last only one. Reissue those two public
          # certificates on day one with the CA's lifetime; private keys and
          # the client trust anchor are explicitly preserved by this command.
          ${lib.getExe velociraptor} \
            --config "$temporary_config" config reissue_certs \
            --validity 3650 > "$reissued_config"
          ${pkgs.coreutils}/bin/mv -- "$reissued_config" "$temporary_config"
        else
          ${lib.getExe velociraptor} \
            --config ${lib.escapeShellArg configFile} config show \
            --merge_file ${configMerge} > "$temporary_config"
        fi

        ${lib.getExe velociraptor} \
          --config "$temporary_config" config show >/dev/null
        ${pkgs.coreutils}/bin/chmod 0600 "$temporary_config"
        ${pkgs.coreutils}/bin/mv -- "$temporary_config" ${lib.escapeShellArg configFile}
        trap - EXIT

        if [[ ! -e ${lib.escapeShellArg adminMarker} ]]; then
          if [[ ! -s ${lib.escapeShellArg adminPasswordFile} ]]; then
            ${pkgs.openssl}/bin/openssl rand -base64 36 | \
              ${pkgs.coreutils}/bin/tr -d '\n' > ${lib.escapeShellArg adminPasswordFile}
            printf '\n' >> ${lib.escapeShellArg adminPasswordFile}
            ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg adminPasswordFile}
          fi

          password=$(${pkgs.coreutils}/bin/tr -d '\n' < ${lib.escapeShellArg adminPasswordFile})
          ${lib.getExe velociraptor} \
            --config ${lib.escapeShellArg configFile} \
            user add --role administrator admin "$password"
          unset password

          ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg adminMarker}
          ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg adminMarker}
        fi

        ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg runtimeReadyMarker}
        ${pkgs.coreutils}/bin/chmod 0444 ${lib.escapeShellArg runtimeReadyMarker}
      '';

      healthCheck = pkgs.writeShellScript "hound-velociraptor-health" ''
        set -o errexit -o nounset -o pipefail

        browser_status=$(${pkgs.curl}/bin/curl \
          --silent --show-error --location \
          --connect-timeout 3 --max-time 20 \
          --cacert ${inputs.self}/certs/ThornCloud_CA.crt \
          --resolve ${hostname}:443:127.0.0.1 \
          --output /dev/null \
          --write-out '%{http_code}' \
          https://${hostname}/app/index.html)

        # Basic authentication deliberately challenges unauthenticated health
        # requests. Requiring that exact response verifies nginx, trusted TLS,
        # the reverse proxy, and the Velociraptor GUI without storing an
        # administrator credential in the probe.
        if [[ "$browser_status" != 401 ]]; then
          echo "error: expected Hound GUI authentication challenge, got HTTP $browser_status" >&2
          exit 1
        fi

        # Browser TLS above renews every 24 hours through Anvil. Independently
        # verify the Velociraptor-internal certificate clients fetch from
        # /server.pem retains at least 30 days of validity.
        ${pkgs.curl}/bin/curl \
          --fail --silent --show-error --insecure \
          --connect-timeout 3 --max-time 20 \
          https://127.0.0.1:8000/server.pem | \
          ${lib.getExe pkgs.openssl} x509 -checkend 2592000 -noout
      '';

      adminPasswordCommand = pkgs.writeShellApplication {
        name = "hound-admin-password";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if ((EUID != 0)); then
            echo "error: hound-admin-password must run as root" >&2
            exit 1
          fi
          if [[ ! -s ${lib.escapeShellArg adminPasswordFile} ]]; then
            echo "error: Hound has not finished creating its administrator" >&2
            exit 1
          fi

          printf 'Username: admin\nPassword: '
          cat ${lib.escapeShellArg adminPasswordFile}
          echo "Change this generated bootstrap password after the first login."
        '';
      };

      exportClientConfigCommand = pkgs.writeShellApplication {
        name = "hound-export-client-config";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if ((EUID != 0)); then
            echo "error: hound-export-client-config must run as root" >&2
            exit 1
          fi
          if (($# != 1)); then
            echo "usage: hound-export-client-config /absolute/output/client.config.yaml" >&2
            exit 2
          fi
          if [[ "$1" != /* ]]; then
            echo "error: output path must be absolute" >&2
            exit 2
          fi
          if [[ -e "$1" ]]; then
            echo "error: refusing to overwrite existing output: $1" >&2
            exit 1
          fi

          temporary_output=$(mktemp "$1.tmp.XXXXXX")
          trap 'rm -f -- "$temporary_output"' EXIT
          ${lib.getExe velociraptor} \
            --config ${lib.escapeShellArg configFile} config client > "$temporary_output"
          chmod 0600 "$temporary_output"
          chown root:root "$temporary_output"
          mv -- "$temporary_output" "$1"
          trap - EXIT
          echo "Wrote root-only enrollment configuration to $1"
        '';
      };

      configCheck = pkgs.runCommand "hound-velociraptor-config-check" { } ''
        export HOME="$TMPDIR"
        mkdir -m 0700 "$TMPDIR/datastore"
        ${lib.getExe velociraptor} config generate \
          --merge_file ${configMerge} > "$TMPDIR/server.config.yaml"
        chmod 0600 "$TMPDIR/server.config.yaml"
        ${lib.getExe velociraptor} \
          --config "$TMPDIR/server.config.yaml" config show >/dev/null
        grep -F 'hound.guildedthorn.arpa' "$TMPDIR/server.config.yaml" >/dev/null
        touch "$out"
      '';
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "hound";
          message = "services-velociraptor is a fixed service profile for the hound host";
        }
        {
          assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          message = "Hound's pinned Velociraptor release is for x86_64-linux";
        }
      ];

      system.checks = [ configCheck ];

      users = {
        groups.velociraptor = { };
        users.velociraptor = {
          isSystemUser = true;
          group = "velociraptor";
          home = stateDirectory;
        };
      };

      environment.systemPackages = [
        adminPasswordCommand
        exportClientConfigCommand
        velociraptor
      ];

      systemd.services = {
        hound-velociraptor-bootstrap = {
          description = "Create Hound Velociraptor cryptographic state and administrator";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          before = [
            "nginx.service"
            "velociraptor-server.service"
          ];
          restartTriggers = [
            bootstrap
            configMerge
            velociraptor
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "velociraptor";
            Group = "velociraptor";
            ExecStart = bootstrap;
            StateDirectory = "velociraptor";
            StateDirectoryMode = "0700";
            RuntimeDirectory = "hound";
            RuntimeDirectoryMode = "0755";
            RuntimeDirectoryPreserve = "yes";
            TimeoutStartSec = "15min";
          };
        };

        velociraptor-server = {
          description = "Hound Velociraptor frontend and GUI backend";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          requires = [ "hound-velociraptor-bootstrap.service" ];
          after = [
            "hound-velociraptor-bootstrap.service"
            "network-online.target"
          ];
          restartTriggers = [
            configMerge
            velociraptor
          ];
          serviceConfig = {
            User = "velociraptor";
            Group = "velociraptor";
            ExecStart = "${lib.getExe velociraptor} --config ${configFile} frontend";
            Restart = "on-failure";
            RestartSec = "10s";
            StateDirectory = "velociraptor";
            StateDirectoryMode = "0700";
            WorkingDirectory = stateDirectory;
            UMask = "0077";
            LimitNOFILE = 65536;

            CapabilityBoundingSet = "";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            RemoveIPC = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            SystemCallArchitectures = "native";
          };
        };

        hound-velociraptor-health = {
          description = "Verify Hound Velociraptor through trusted HTTPS";
          requires = [
            "nginx.service"
            "velociraptor-server.service"
          ];
          after = [
            "nginx.service"
            "velociraptor-server.service"
          ];
          unitConfig.ConditionPathExists = runtimeReadyMarker;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = healthCheck;
            TimeoutStartSec = "30s";
          };
        };

        nginx = {
          wants = [ "velociraptor-server.service" ];
          after = [ "velociraptor-server.service" ];
        };
      };

      systemd.timers.hound-velociraptor-health = {
        description = "Frequent Hound Velociraptor health verification";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "5m";
          AccuracySec = "1m";
          Unit = "hound-velociraptor-health.service";
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
            # The trusted local health probe connects through this vhost. This
            # does not expose the GUI externally; loopback cannot arrive from
            # another machine, and the backend is already loopback-only.
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
            proxyPass = "https://127.0.0.1:8889";
            proxyWebsockets = true;
            extraConfig = ''
              if (!-f ${runtimeReadyMarker}) {
                return 503;
              }

              # The backend certificate is signed by Velociraptor's private
              # internal CA and never leaves loopback. ThornCloud_CA protects
              # the browser-facing connection above.
              proxy_ssl_verify off;
              proxy_ssl_server_name on;
              proxy_ssl_name ${hostname};
              proxy_buffering off;
              proxy_read_timeout 600s;
              proxy_send_timeout 600s;
            '';
          };
        };
      };
    };
}
