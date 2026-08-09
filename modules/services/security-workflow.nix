{ ... }:
{
  nixos.modules.services-security-workflow =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.securityWorkflow;
      relaySource = ./security_alert_relay.py;
      relayTestsSource = ./security_alert_relay_test.py;
      relayPackage = pkgs.writeShellApplication {
        name = "thorn-security-relay";
        runtimeInputs = [ pkgs.python3 ];
        text = ''
          exec python3 ${relaySource} "$@"
        '';
      };
      relayTests =
        pkgs.runCommand "thorn-security-relay-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            export PYTHONPATH=${./.}
            python3 ${relayTestsSource}
            touch "$out"
          '';
    in
    {
      options.thorn.securityWorkflow = {
        enable = lib.mkEnableOption "Grafana to OpenCTI and TheHive security workflow";
        theHiveUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://casebook.guildedthorn.arpa";
          description = "Trusted HTTPS base URL for TheHive.";
        };
        theHiveApiKeyFile = lib.mkOption {
          type = lib.types.path;
          description = "Root-readable file containing the TheHive service-account API key.";
        };
        openCtiUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://oracle.guildedthorn.arpa";
          description = "Trusted HTTPS base URL for OpenCTI.";
        };
        openCtiApiTokenFile = lib.mkOption {
          type = lib.types.path;
          description = "Root-readable file containing the OpenCTI read-only service-account token.";
        };
        hmacSecretFile = lib.mkOption {
          type = lib.types.path;
          description = "Root-readable shared key used to authenticate Grafana webhook bodies.";
        };
        listenPort = lib.mkOption {
          type = lib.types.port;
          default = 9088;
          description = "Loopback-only Grafana webhook and metrics port.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = lib.hasPrefix "https://" cfg.theHiveUrl;
            message = "thorn.securityWorkflow.theHiveUrl must use HTTPS";
          }
          {
            assertion = lib.hasPrefix "https://" cfg.openCtiUrl;
            message = "thorn.securityWorkflow.openCtiUrl must use HTTPS";
          }
        ];

        system.checks = [ relayTests ];
        environment.systemPackages = [ relayPackage ];

        systemd.services.thorn-security-relay = {
          description = "Enrich critical Grafana security alerts and create TheHive alerts";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "sops-nix.service"
          ];
          requires = [ "sops-nix.service" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${relayPackage}/bin/thorn-security-relay serve";
            Restart = "on-failure";
            RestartSec = "5s";

            DynamicUser = true;
            StateDirectory = "thorn-security-relay";
            StateDirectoryMode = "0700";
            LoadCredential = [
              "thehive-api-key:${cfg.theHiveApiKeyFile}"
              "opencti-api-token:${cfg.openCtiApiTokenFile}"
              "grafana-webhook-hmac:${cfg.hmacSecretFile}"
            ];

            AmbientCapabilities = "";
            CapabilityBoundingSet = "";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
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
            ProtectProc = "invisible";
            ProtectSystem = "strict";
            RemoveIPC = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            UMask = "0077";
            MemoryMax = "256M";
            TasksMax = 64;
          };
          environment = {
            SECURITY_RELAY_LISTEN_HOST = "127.0.0.1";
            SECURITY_RELAY_LISTEN_PORT = toString cfg.listenPort;
            SECURITY_RELAY_STATE_FILE = "/var/lib/thorn-security-relay/state.json";
            SECURITY_RELAY_THEHIVE_URL = cfg.theHiveUrl;
            SECURITY_RELAY_OPENCTI_URL = cfg.openCtiUrl;
            SECURITY_RELAY_CA_FILE = config.security.pki.caBundle;
          };
        };

        services.prometheus.scrapeConfigs = lib.mkAfter [
          {
            job_name = "security-relay";
            static_configs = [ { targets = [ "127.0.0.1:${toString cfg.listenPort}" ]; } ];
            metrics_path = "/metrics";
          }
        ];
      };
    };
}
