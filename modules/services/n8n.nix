{ inputs, ... }:
{
  nixos.modules.services-n8n-loom =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "loom.guildedthorn.arpa";
      secretStateDirectory = "/var/lib/loom-n8n-secrets";
      seedStateDirectory = "/var/lib/loom-n8n-seed";
      modelCredentialDirectory = "/var/lib/loom-model-workflows-credential";
      # The external task-runner launcher owns 5680 and allocates adjacent
      # health ports to its JavaScript/Python runners. Keep the policy gateway
      # outside that range so an n8n restart cannot starve workflow execution.
      modelGatewayPort = 5689;
      modelEditableWorkflowIds = [
        "6ZtXlBrFI0nGZ5R2"
        "CasitaEspnSports"
        "ThornChangeWindowPreflight"
        "ThornFleetHealth"
        "ThornHydraStatus"
        "ThornN8nFailure"
        "ThornThreatNewsCorrelation"
        "ThornWeeklyMaintenanceQueue"
      ];
      starterWorkflowDirectory = ../../hosts/loom/workflows;
      caalEspnWorkflowSource = pkgs.fetchurl {
        name = "caal-espn-1.0.0.json";
        # Personal, non-commercial use under the CAAL Tool Registry License.
        # ESPN tool author: cmac86; registry maintained by CoreWorxLab.
        url = "https://raw.githubusercontent.com/CoreWorxLab/caal-tools/2ed43969082ab892e6c024f5c21d3ae8b9ff2aa6/tools/sports/espn/workflow.json";
        hash = "sha256-TRmieVS/24meYVyhi7qydQYWqNs88L1ZnJdnr7yJxhw=";
      };
      caalEspnWorkflow =
        pkgs.runCommand "casita-espn-workflow.json" { nativeBuildInputs = [ pkgs.jq ]; }
          ''
            # n8n 2.35 rejects the two upstream sticky notes sharing a name.
            # Rename only the registry-attribution note; executable nodes and
            # their connections remain byte-for-byte equivalent upstream.
            jq '
              .id = "CasitaEspnSports" |
              .name = "Casita | ESPN sports" |
              (.nodes[] |
                select(.id == "b7d0b124-bd77-4cf8-8c11-f0702f9c5924") |
                .name) = "CAAL Registry Tracking"
            ' \
              ${caalEspnWorkflowSource} > "$out"
          '';
      workflowFilesDirectory = "/var/lib/n8n-files";
      # Keep the security override isolated from the rest of the fleet's
      # nixpkgs package set. See packages/n8n.nix for the pinned advisory.
      n8nPackage = pkgs.callPackage ../../packages/n8n.nix { };
      modelGatewaySource = ../../packages/loom_model_workflows.py;
      modelGatewayTestsSource = ../../packages/loom_model_workflows_test.py;
      modelGatewayPackage = pkgs.writeShellApplication {
        name = "loom-model-workflows";
        runtimeInputs = [ pkgs.python3 ];
        text = ''
          exec python3 ${modelGatewaySource} "$@"
        '';
      };
      modelGatewayTests =
        pkgs.runCommand "loom-model-workflows-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            export PYTHONPATH=${../../packages}
            python3 ${modelGatewayTestsSource}
            touch "$out"
          '';
      enableModelWorkflowAccess = pkgs.writeShellScript "enable-loom-model-workflows" ''
        set -o errexit -o nounset -o pipefail

        ${config.services.postgresql.package}/bin/psql \
          --host=/run/postgresql \
          --dbname=n8n \
          --username=n8n \
          --set=ON_ERROR_STOP=1 \
          --command="UPDATE workflow_entity
            SET settings = jsonb_set(
              COALESCE(settings::jsonb, '{}'::jsonb),
              '{availableInMCP}',
              'true'::jsonb,
              true
            )::json
            WHERE id IN (${lib.concatMapStringsSep ", " (id: "'${id}'") modelEditableWorkflowIds})
              AND COALESCE(settings::jsonb ->> 'availableInMCP', 'false') <> 'true';"
      '';
      createSecrets = pkgs.writeShellScript "loom-n8n-create-secrets" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        for secret_name in encryption-key runner-auth-token; do
          secret_path=${secretStateDirectory}/$secret_name
          if [[ ! -s "$secret_path" ]]; then
            ${pkgs.openssl}/bin/openssl rand -hex 32 \
              | ${pkgs.coreutils}/bin/tr -d '\r\n' > "$secret_path.new"
          else
            # n8n deliberately does not trim _FILE values. Older Loom
            # generations wrote OpenSSL's trailing newline, causing runner
            # authentication warnings and potentially a token mismatch.
            normalized=$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret_path")
            if [[ ! "$normalized" =~ ^[[:xdigit:]]{64}$ ]]; then
              echo "error: refusing to rewrite malformed $secret_path" >&2
              exit 1
            fi
            printf '%s' "$normalized" > "$secret_path.new"
            unset normalized
          fi

          chmod 0400 "$secret_path.new"
          if ! ${pkgs.diffutils}/bin/cmp --silent "$secret_path.new" "$secret_path"; then
            mv -T "$secret_path.new" "$secret_path"
          else
            rm -f "$secret_path.new"
          fi
        done
      '';
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "loom";
          message = "services-n8n-loom is a fixed service profile for the loom host";
        }
      ];

      system.checks = [ modelGatewayTests ];

      # n8n stores workflow metadata in a local PostgreSQL database. Peer
      # authentication binds the database role to systemd's dynamic `n8n`
      # service identity, so no reusable database password exists.
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_16;
        ensureDatabases = [ "n8n" ];
        ensureUsers = [
          {
            name = "n8n";
            ensureDBOwnership = true;
          }
        ];
        settings = {
          listen_addresses = lib.mkForce "";
          password_encryption = "scram-sha-256";
        };
      };

      services.postgresqlBackup = {
        enable = true;
        databases = [ "n8n" ];
        startAt = "*-*-* 03:30:00";
        compression = "zstd";
        pgdumpOptions = "";
      };

      thorn.backup = {
        enable = true;
        schedule = "*-*-* 03:50:00";
        paths = [
          "/var/backup/postgresql"
          secretStateDirectory
          "/var/lib/private/n8n"
        ];
        restorePaths = [ "${secretStateDirectory}/encryption-key" ];
        postgresDumps.n8n = "/var/backup/postgresql/n8n.sql.zstd";
      };

      # Generate installation-specific secrets on the VM at first boot. They
      # never enter Git, flake evaluation, the Nix store, or process argv;
      # systemd copies them into private credential directories for n8n and
      # its external task runners.
      systemd.services.loom-n8n-secrets = {
        description = "Create Loom n8n installation secrets";
        before = [
          "n8n.service"
          "n8n-task-runner.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "loom-n8n-secrets";
          StateDirectoryMode = "0700";
          UMask = "0077";
          ExecStart = createSecrets;
          RemainAfterExit = true;
        };
      };

      users.groups.n8n-files = { };
      systemd.tmpfiles.rules = [
        "d ${workflowFilesDirectory} 0770 root n8n-files -"
      ];

      services.n8n = {
        enable = true;
        package = n8nPackage;
        openFirewall = false;
        environment = {
          N8N_LISTEN_ADDRESS = "127.0.0.1";
          N8N_HOST = hostname;
          N8N_PORT = 5678;
          N8N_PROTOCOL = "https";
          N8N_EDITOR_BASE_URL = "https://${hostname}/";
          N8N_WEBHOOK_URL = "https://${hostname}/";
          N8N_PROXY_HOPS = 1;

          DB_TYPE = "postgresdb";
          DB_POSTGRESDB_HOST = "/run/postgresql";
          DB_POSTGRESDB_PORT = 5432;
          DB_POSTGRESDB_DATABASE = "n8n";
          DB_POSTGRESDB_USER = "n8n";
          DB_POSTGRESDB_SCHEMA = "public";
          DB_POSTGRESDB_POOL_SIZE = 10;

          N8N_ENCRYPTION_KEY_FILE = "${secretStateDirectory}/encryption-key";
          N8N_RUNNERS_AUTH_TOKEN_FILE = "${secretStateDirectory}/runner-auth-token";

          # Treat every workflow as potentially hostile. Code nodes execute
          # in external runners, environment access is hidden, local file
          # access is confined to a dedicated exchange directory, arbitrary
          # host command execution is disabled, and community packages stay
          # off until explicitly reviewed and packaged.
          N8N_BLOCK_ENV_ACCESS_IN_NODE = true;
          N8N_BLOCK_FILE_ACCESS_TO_N8N_FILES = true;
          N8N_RESTRICT_FILE_ACCESS_TO = workflowFilesDirectory;
          N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = true;
          N8N_COMMUNITY_PACKAGES_ENABLED = false;
          N8N_UNVERIFIED_PACKAGES_ENABLED = false;
          N8N_COMMUNITY_PACKAGES_MANAGED_BY_ENV = true;
          N8N_COMMUNITY_PACKAGES = "";
          NODES_EXCLUDE = ''["n8n-nodes-base.executeCommand"]'';

          # Expose n8n's authenticated instance-level MCP server so local
          # coding agents can inspect and build workflows. Keep the setting
          # declarative, keep MCP Apps/registry disabled, and retain the node
          # sandbox below: every MCP client must authenticate as an n8n user
          # and cannot silently add a new outbound trust path.
          N8N_AI_ENABLED = false;
          N8N_AI_ALLOW_SENDING_PARAMETER_VALUES = false;
          N8N_MCP_MANAGED_BY_ENV = true;
          N8N_MCP_ACCESS_ENABLED = true;
          N8N_MCP_BUILDER_ENABLED = true;
          N8N_MCP_APPS_ENABLED = false;
          N8N_MCP_SERVER_RATE_LIMIT = 100;
          N8N_MCP_MAX_REGISTERED_CLIENTS = 8;
          N8N_DISABLE_PUBLIC_CHAT_TRIGGER = true;
          N8N_DISABLED_MODULES = "mcp-registry,workflow-builder,chat-hub";

          # Keep the authenticated API available for future ThornixOS
          # automation, but do not publish its interactive documentation.
          N8N_PUBLIC_API_DISABLED = false;
          N8N_PUBLIC_API_SWAGGERUI_DISABLED = true;
          N8N_PUBLIC_API_PACKAGES_ENABLED = false;

          # Block requests to private IP literals while permitting the
          # controlled internal DNS namespace used by ThornixOS services.
          N8N_SSRF_PROTECTION_ENABLED = true;
          N8N_SSRF_ALLOWED_HOSTNAMES = "*.guildedthorn.arpa";

          N8N_DIAGNOSTICS_ENABLED = false;
          N8N_VERSION_NOTIFICATIONS_ENABLED = false;
          N8N_TEMPLATES_ENABLED = false;
          N8N_PERSONALIZATION_ENABLED = false;
          N8N_HIRING_BANNER_ENABLED = false;
          N8N_SECURE_COOKIE = true;
          N8N_SAMESITE_COOKIE = "lax";
          NODE_EXTRA_CA_CERTS = config.security.pki.caBundle;

          N8N_METRICS = true;
          N8N_METRICS_INCLUDE_DEFAULT_METRICS = true;
          N8N_LOG_LEVEL = "info";
          N8N_LOG_OUTPUT = "console";

          # Bound CPU/memory pressure on this 2-vCPU, 4-GiB automation host.
          N8N_CONCURRENCY_PRODUCTION_LIMIT = 4;
          EXECUTIONS_TIMEOUT = 1800;
          EXECUTIONS_TIMEOUT_MAX = 3600;
          EXECUTIONS_DATA_PRUNE = true;
          EXECUTIONS_DATA_MAX_AGE = 336;
          EXECUTIONS_DATA_PRUNE_MAX_COUNT = 10000;
          N8N_DEFAULT_BINARY_DATA_MODE = "filesystem";
          N8N_RUNNERS_TASK_TIMEOUT = 300;
          # Adopt the next release's safer decompression bounds now instead
          # of retaining the legacy 2-GiB / 5000-entry defaults.
          N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES = 268435456;
          N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES = 1000;
        };

        taskRunners = {
          enable = true;
          environment = {
            N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT = 15;
            N8N_RUNNERS_MAX_CONCURRENCY = 4;
            N8N_RUNNERS_TASK_TIMEOUT = 300;
            NODE_EXTRA_CA_CERTS = config.security.pki.caBundle;
            SSL_CERT_FILE = config.security.pki.caBundle;
            REQUESTS_CA_BUNDLE = config.security.pki.caBundle;
          };
        };
      };

      systemd.services.n8n = {
        restartTriggers = [ createSecrets ];
        requires = [
          "loom-n8n-secrets.service"
          "postgresql.target"
        ];
        after = [
          "loom-n8n-secrets.service"
          "network-online.target"
          "postgresql.target"
        ];
        wants = [
          "loom-model-workflows-access.service"
          "loom-model-workflows-credential.service"
          "loom-model-workflows.service"
          "network-online.target"
        ];
        serviceConfig = {
          StateDirectoryMode = "0700";
          SupplementaryGroups = [ "n8n-files" ];
          ReadWritePaths = [ workflowFilesDirectory ];
          UMask = "0077";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
        };
      };

      systemd.services.n8n-task-runner = {
        restartTriggers = [ createSecrets ];
        after = [ "loom-n8n-secrets.service" ];
        requires = [ "loom-n8n-secrets.service" ];
        partOf = [ "n8n.service" ];
        serviceConfig = {
          StateDirectoryMode = "0700";
          SupplementaryGroups = [ "n8n-files" ];
          ReadWritePaths = [ workflowFilesDirectory ];
          UMask = "0077";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
        };
      };

      # Keep n8n's MCP credential on Loom.  Casita talks only to the policy
      # gateway below; neither Home Assistant nor its local language model can
      # recover or bypass the bearer token.  Refreshing this oneshot after an
      # MCP-key rotation updates the private source credential for a gateway
      # restart without placing the key in Git or the Nix store.
      systemd.services.loom-model-workflows-credential = {
        description = "Stage Loom's n8n MCP credential for the model policy gateway";
        partOf = [ "n8n.service" ];
        after = [
          "n8n.service"
          "postgresql.service"
        ];
        requires = [
          "n8n.service"
          "postgresql.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "n8n";
          Group = "n8n";
          DynamicUser = true;
          StateDirectory = "loom-model-workflows-credential";
          StateDirectoryMode = "0700";
          UMask = "0077";
          RemainAfterExit = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ modelCredentialDirectory ];
          ExecStart = pkgs.writeShellScript "stage-loom-model-mcp-token" ''
            set -o errexit -o nounset -o pipefail

            token="$(${config.services.postgresql.package}/bin/psql \
              --host=/run/postgresql \
              --dbname=n8n \
              --username=n8n \
              --no-align \
              --tuples-only \
              --command="SELECT \"apiKey\" FROM user_api_keys WHERE audience = 'mcp-server-api' ORDER BY \"updatedAt\" DESC LIMIT 1;")"
            token="$(${pkgs.coreutils}/bin/printf '%s' "$token" | ${pkgs.coreutils}/bin/tr -d '\r\n')"
            if [[ ! "$token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
              echo "error: n8n MCP access must be enabled once in the owner settings" >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/printf '%s' "$token" > ${modelCredentialDirectory}/n8n-mcp-token.new
            unset token
            ${pkgs.coreutils}/bin/chmod 0400 ${modelCredentialDirectory}/n8n-mcp-token.new
            if ! ${pkgs.diffutils}/bin/cmp --silent \
              ${modelCredentialDirectory}/n8n-mcp-token.new \
              ${modelCredentialDirectory}/n8n-mcp-token; then
              ${pkgs.coreutils}/bin/mv -T \
                ${modelCredentialDirectory}/n8n-mcp-token.new \
                ${modelCredentialDirectory}/n8n-mcp-token
            else
              ${pkgs.coreutils}/bin/rm -f ${modelCredentialDirectory}/n8n-mcp-token.new
            fi
          '';
        };
      };

      # n8n's builder refuses details and mutations until a workflow is marked
      # available to MCP. Enable only the known declarative operational tools;
      # personal IDs remain unavailable in addition to the gateway's
      # independent ID/name/tag protections. The timer catches starter imports
      # that may occur after the first boot attempt.
      systemd.services.loom-model-workflows-access = {
        description = "Enable known non-personal Loom workflows for model editing";
        wantedBy = [ "multi-user.target" ];
        partOf = [ "n8n.service" ];
        after = [
          "n8n.service"
          "postgresql.service"
        ];
        requires = [
          "n8n.service"
          "postgresql.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "n8n";
          Group = "n8n";
          DynamicUser = true;
          ExecStart = enableModelWorkflowAccess;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      };

      systemd.timers.loom-model-workflows-access = {
        description = "Reconcile model-editable Loom workflow access";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "5m";
          AccuracySec = "15s";
          Unit = "loom-model-workflows-access.service";
        };
      };

      systemd.services.loom-model-workflows = {
        description = "Policy-enforced draft workflow tools for Casita";
        wantedBy = [ "multi-user.target" ];
        partOf = [ "n8n.service" ];
        after = [
          "loom-model-workflows-access.service"
          "loom-model-workflows-credential.service"
          "n8n.service"
          "network-online.target"
        ];
        requires = [
          "loom-model-workflows-access.service"
          "loom-model-workflows-credential.service"
          "n8n.service"
        ];
        wants = [ "network-online.target" ];
        environment = {
          LOOM_MODEL_LISTEN_HOST = "127.0.0.1";
          LOOM_MODEL_LISTEN_PORT = toString modelGatewayPort;
          LOOM_MODEL_MCP_URL = "http://127.0.0.1:5678/mcp-server/http";
          LOOM_MODEL_PROTECTED_IDS = lib.concatStringsSep "," [
            "ThornEveningDrop"
            "ThornFrictionToFix"
            "ThornMorningOperatorBrief"
            "ThornNightBrainDump"
            "ThornRestartCapsule"
          ];
          LOOM_MODEL_PROTECTED_NAMES = lib.concatStringsSep "," [
            "Thorn | Evening drop"
            "Thorn | Friction-to-fix pipeline"
            "Thorn | Morning operator brief"
            "Thorn | Night brain dump"
            "Thorn | Restart capsule"
          ];
          LOOM_MODEL_PROTECTED_TAGS = "personal,protected,casita-protected";
          LOOM_MODEL_PROTECTED_PREFIXES = "Thorn |";
        };
        serviceConfig = {
          Type = "simple";
          ExecStart = "${modelGatewayPackage}/bin/loom-model-workflows";
          Restart = "on-failure";
          RestartSec = "3s";
          DynamicUser = true;
          LoadCredential = "n8n_mcp_token:${modelCredentialDirectory}/n8n-mcp-token";

          AmbientCapabilities = "";
          CapabilityBoundingSet = "";
          IPAddressAllow = [
            "127.0.0.0/8"
            "::1/128"
          ];
          IPAddressDeny = "any";
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
          MemoryMax = "192M";
          TasksMax = 32;
        };
      };

      # Import a starter pack after the first owner account is created. Each
      # workflow gets its own immutable marker: later additions are imported
      # automatically, while deployments never overwrite a workflow that has
      # since been edited in the UI. The pinned, credential-free CAAL ESPN tool
      # is the sole auto-published starter; all ThornixOS workflows stay
      # inactive. A timer handles both the already-configured VM and clean
      # reinstalls where owner setup happens after the first boot.
      systemd.services.loom-n8n-workflow-seed = {
        description = "Seed Loom n8n starter workflows";
        after = [
          "loom-n8n-secrets.service"
          "n8n.service"
          "postgresql.service"
        ];
        requires = [
          "loom-n8n-secrets.service"
          "n8n.service"
          "postgresql.service"
        ];
        environment = {
          DB_TYPE = "postgresdb";
          DB_POSTGRESDB_HOST = "/run/postgresql";
          DB_POSTGRESDB_PORT = "5432";
          DB_POSTGRESDB_DATABASE = "n8n";
          DB_POSTGRESDB_USER = "n8n";
          DB_POSTGRESDB_SCHEMA = "public";
          # The main n8n StateDirectory is id-mapped for its DynamicUser and
          # intentionally inaccessible from this separate oneshot. Keep the
          # import CLI's private config in the seed service's own state.
          N8N_USER_FOLDER = seedStateDirectory;
          N8N_ENCRYPTION_KEY_FILE = "%d/n8n_encryption_key_file";
          NODE_EXTRA_CA_CERTS = config.security.pki.caBundle;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "n8n";
          Group = "n8n";
          DynamicUser = true;
          StateDirectory = "loom-n8n-seed";
          StateDirectoryMode = "0700";
          LoadCredential = "n8n_encryption_key_file:${secretStateDirectory}/encryption-key";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ seedStateDirectory ];
          ExecStart = pkgs.writeShellScript "loom-n8n-seed-workflows" ''
            set -o errexit -o nounset -o pipefail
            shopt -s nullglob

            owner_count="$(${config.services.postgresql.package}/bin/psql \
              --host=/run/postgresql \
              --dbname=n8n \
              --username=n8n \
              --no-align \
              --tuples-only \
              --command='SELECT count(*) FROM "user";')"

            if (( owner_count == 0 )); then
              echo "n8n owner setup is incomplete; starter import deferred"
              exit 0
            fi

            for workflow in ${starterWorkflowDirectory}/*.json; do
              workflow_name="$(${pkgs.coreutils}/bin/basename "$workflow")"
              if [[ "$workflow_name" == "nascar-scores.json" ]]; then
                continue
              fi
              marker=${seedStateDirectory}/$workflow_name.imported
              if [[ -e "$marker" ]]; then
                continue
              fi

              ${n8nPackage}/bin/n8n import:workflow --input="$workflow"
              ${pkgs.coreutils}/bin/touch "$marker"
            done

            nascar_marker=${seedStateDirectory}/nascar-scores.imported
            if [[ ! -e "$nascar_marker" ]]; then
              nascar_exists="$(${config.services.postgresql.package}/bin/psql \
                --host=/run/postgresql \
                --dbname=n8n \
                --username=n8n \
                --no-align \
                --tuples-only \
                --command="SELECT count(*) FROM workflow_entity WHERE id = '6ZtXlBrFI0nGZ5R2';")"
              if (( nascar_exists == 0 )); then
                ${n8nPackage}/bin/n8n import:workflow \
                  --input=${starterWorkflowDirectory}/nascar-scores.json
              fi
              ${n8nPackage}/bin/n8n publish:workflow --id=6ZtXlBrFI0nGZ5R2
              ${pkgs.coreutils}/bin/touch "$nascar_marker"
            fi

            espn_marker=${seedStateDirectory}/caal-espn-1.0.0.imported
            if [[ ! -e "$espn_marker" ]]; then
              espn_exists="$(${config.services.postgresql.package}/bin/psql \
                --host=/run/postgresql \
                --dbname=n8n \
                --username=n8n \
                --no-align \
                --tuples-only \
                --command="SELECT count(*) FROM workflow_entity WHERE id = 'CasitaEspnSports';")"
              if (( espn_exists == 0 )); then
                ${n8nPackage}/bin/n8n import:workflow --input=${caalEspnWorkflow}
              fi
              ${n8nPackage}/bin/n8n publish:workflow --id=CasitaEspnSports
              ${pkgs.coreutils}/bin/touch "$espn_marker"
            fi
          '';
        };
      };

      systemd.timers.loom-n8n-workflow-seed = {
        description = "Retry Loom n8n starter workflow import after owner setup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "5m";
          AccuracySec = "15s";
          Unit = "loom-n8n-workflow-seed.service";
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
            add_header Strict-Transport-Security "max-age=31536000" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header X-Frame-Options "SAMEORIGIN" always;
            add_header Referrer-Policy "same-origin" always;
            add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
            client_max_body_size 64m;
          '';
          locations = {
            "= /metrics" = {
              proxyPass = "http://127.0.0.1:5678";
              extraConfig = ''
                allow 172.16.25.51;
                deny all;
              '';
            };
            # Streamable HTTP MCP endpoint. Authentication and per-user tool
            # authorization remain in n8n; the edge only disables buffering
            # so long-lived MCP responses are delivered immediately.
            "= /mcp-server/http" = {
              proxyPass = "http://127.0.0.1:5678";
              extraConfig = ''
                proxy_buffering off;
                proxy_request_buffering off;
                proxy_read_timeout 300s;
                proxy_send_timeout 300s;
              '';
            };
            "= /model-workflows/health" = {
              proxyPass = "http://127.0.0.1:${toString modelGatewayPort}/health";
              extraConfig = ''
                allow 172.16.25.2;
                allow 172.16.25.51;
                deny all;
                proxy_buffering off;
              '';
            };
            "= /model-workflows/v1/call" = {
              proxyPass = "http://127.0.0.1:${toString modelGatewayPort}/v1/call";
              extraConfig = ''
                allow 172.16.25.2;
                deny all;
                client_max_body_size 96k;
                if ($request_method != POST) {
                  return 405;
                }
                proxy_buffering off;
                proxy_request_buffering off;
                proxy_connect_timeout 5s;
                proxy_read_timeout 60s;
                proxy_send_timeout 60s;
              '';
            };
            "= /webhook/espn" = {
              proxyPass = "http://127.0.0.1:5678";
              extraConfig = ''
                allow 172.16.25.2;
                deny all;
                client_max_body_size 8k;
                if ($request_method != POST) {
                  return 405;
                }
                proxy_buffering off;
                proxy_request_buffering off;
                proxy_connect_timeout 5s;
                proxy_read_timeout 20s;
                proxy_send_timeout 20s;
              '';
            };
            "/" = {
              proxyPass = "http://127.0.0.1:5678";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_buffering off;
                proxy_read_timeout 300s;
                proxy_send_timeout 300s;
              '';
            };
          };
        };
      };

      systemd.services.nginx = {
        wants = [
          "loom-model-workflows.service"
          "n8n.service"
        ];
        after = [
          "loom-model-workflows.service"
          "n8n.service"
        ];
      };

      environment.systemPackages = [
        modelGatewayPackage
        n8nPackage
      ];
    };
}
