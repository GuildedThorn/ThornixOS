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
      workflowFilesDirectory = "/var/lib/n8n-files";
      createSecrets = pkgs.writeShellScript "loom-n8n-create-secrets" ''
        set -o errexit -o nounset -o pipefail

        for secret_name in encryption-key runner-auth-token; do
          secret_path=${secretStateDirectory}/$secret_name
          if [[ ! -s "$secret_path" ]]; then
            ${pkgs.openssl}/bin/openssl rand -hex 32 > "$secret_path.new"
            chmod 0400 "$secret_path.new"
            mv -T "$secret_path.new" "$secret_path"
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
        openFirewall = false;
        environment = {
          N8N_LISTEN_ADDRESS = "127.0.0.1";
          N8N_HOST = hostname;
          N8N_PORT = 5678;
          N8N_PROTOCOL = "https";
          N8N_EDITOR_BASE_URL = "https://${hostname}/";
          WEBHOOK_URL = "https://${hostname}/";
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
          NODES_EXCLUDE = ''["n8n-nodes-base.executeCommand"]'';

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

          EXECUTIONS_DATA_PRUNE = true;
          EXECUTIONS_DATA_MAX_AGE = 336;
          EXECUTIONS_DATA_PRUNE_MAX_COUNT = 10000;
          N8N_DEFAULT_BINARY_DATA_MODE = "filesystem";
        };

        taskRunners = {
          enable = true;
          environment = {
            N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT = 15;
            N8N_RUNNERS_MAX_CONCURRENCY = 4;
            NODE_EXTRA_CA_CERTS = config.security.pki.caBundle;
            SSL_CERT_FILE = config.security.pki.caBundle;
            REQUESTS_CA_BUNDLE = config.security.pki.caBundle;
          };
        };
      };

      systemd.services.n8n = {
        requires = [
          "loom-n8n-secrets.service"
          "postgresql.target"
        ];
        after = [
          "loom-n8n-secrets.service"
          "network-online.target"
          "postgresql.target"
        ];
        wants = [ "network-online.target" ];
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
        wants = [ "n8n.service" ];
        after = [ "n8n.service" ];
      };

      environment.systemPackages = [ pkgs.n8n ];
    };
}
