{ inputs, ... }:
{
  nixos.modules.services-codex =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      certificateName = "codex.guildedthorn.arpa";
      searchHostname = "search.guildedthorn.arpa";
      feedsHostname = "feeds.guildedthorn.arpa";
      credentialsDirectory = "/var/lib/codex";
      searxEnvironment = "${credentialsDirectory}/searx.env";
      minifluxCredentials = "${credentialsDirectory}/miniflux-admin.env";
      feedCatalog = ../../hosts/codex/feeds.tsv;
      backupReady = builtins.pathExists "${inputs.self}/hosts/codex/backup-secrets.yaml";
      showInitialPassword = pkgs.writeShellApplication {
        name = "codex-initial-password";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if [[ $EUID -ne 0 ]]; then
            echo "error: run codex-initial-password as root" >&2
            exit 1
          fi
          if [[ ! -s ${lib.escapeShellArg minifluxCredentials} ]]; then
            echo "error: Codex has not generated Miniflux credentials yet" >&2
            exit 1
          fi
          sed -n 's/^ADMIN_USERNAME=/username: /p; s/^ADMIN_PASSWORD=/password: /p' \
            ${lib.escapeShellArg minifluxCredentials}
        '';
      };
      seedFeeds = pkgs.writeShellApplication {
        name = "codex-seed-feeds";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          jq
        ];
        text = ''
          exec ${pkgs.bash}/bin/bash ${./codex-seed-feeds.sh} ${feedCatalog} "$@"
        '';
      };
    in
    {
      environment.systemPackages = [
        seedFeeds
        showInitialPassword
      ];

      systemd.services.codex-credentials = {
        description = "Generate persistent Codex application credentials";
        wantedBy = [ "multi-user.target" ];
        before = [
          "miniflux.service"
          "searx-init.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "codex";
          StateDirectoryMode = "0700";
          UMask = "0077";
        };
        path = with pkgs; [
          coreutils
          openssl
        ];
        script = ''
          set -o errexit -o nounset -o pipefail

          if [[ ! -s ${lib.escapeShellArg searxEnvironment} ]]; then
            secret=$(openssl rand -hex 32)
            printf 'SEARX_SECRET_KEY=%s\n' "$secret" \
              > ${lib.escapeShellArg searxEnvironment}.new
            chmod 0400 ${lib.escapeShellArg searxEnvironment}.new
            mv -T ${lib.escapeShellArg searxEnvironment}.new \
              ${lib.escapeShellArg searxEnvironment}
            unset secret
          fi

          if [[ ! -s ${lib.escapeShellArg minifluxCredentials} ]]; then
            password=$(openssl rand -hex 24)
            printf 'ADMIN_USERNAME=thorn\nADMIN_PASSWORD=%s\n' "$password" \
              > ${lib.escapeShellArg minifluxCredentials}.new
            chmod 0400 ${lib.escapeShellArg minifluxCredentials}.new
            mv -T ${lib.escapeShellArg minifluxCredentials}.new \
              ${lib.escapeShellArg minifluxCredentials}
            unset password
          fi
        '';
      };

      services.searx = {
        enable = true;
        domain = searchHostname;
        environmentFile = searxEnvironment;
        configureNginx = true;
        settings = {
          general = {
            debug = false;
            instance_name = "GuildedThorn Search";
          };
          search = {
            safe_search = 0;
            autocomplete = "duckduckgo";
            formats = [ "html" ];
          };
          server = {
            secret_key = "$SEARX_SECRET_KEY";
            limiter = false;
            public_instance = false;
            image_proxy = true;
            default_http_headers = {
              X-Content-Type-Options = "nosniff";
              X-Robots-Tag = "noindex, nofollow";
              Referrer-Policy = "no-referrer";
            };
          };
        };
      };

      systemd.services.searx-init = {
        requires = [ "codex-credentials.service" ];
        after = [ "codex-credentials.service" ];
      };

      services.miniflux = {
        enable = true;
        adminCredentialsFile = minifluxCredentials;
        config = {
          BASE_URL = "https://${feedsHostname}/";
          LISTEN_ADDR = "127.0.0.1:8081";
          CREATE_ADMIN = 1;
          RUN_MIGRATIONS = 1;
          WATCHDOG = 1;
        };
      };

      systemd.services.miniflux = {
        requires = [ "codex-credentials.service" ];
        after = [ "codex-credentials.service" ];
      };

      services.postgresql = {
        package = pkgs.postgresql_16;
        settings = {
          listen_addresses = lib.mkForce "";
          password_encryption = "scram-sha-256";
        };
      };
      services.postgresqlBackup = {
        enable = true;
        databases = [ "miniflux" ];
        startAt = "*-*-* 03:30:00";
        compression = "zstd";
        pgdumpOptions = "";
      };

      thorn.backup = lib.mkIf backupReady {
        enable = true;
        schedule = "*-*-* 03:45:00";
        paths = [
          "/var/backup/postgresql"
          credentialsDirectory
        ];
        restorePaths = [ minifluxCredentials ];
        postgresDumps.miniflux = "/var/backup/postgresql/miniflux.sql.zstd";
      };

      thorn.acme = {
        enable = true;
        domain = certificateName;
        extraDomainNames = [
          searchHostname
          feedsHostname
        ];
        group = config.services.nginx.group;
        reloadServices = [ "nginx.service" ];
      };

      services.nginx = {
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        virtualHosts = {
          ${searchHostname} = {
            forceSSL = true;
            useACMEHost = certificateName;
            extraConfig = ''
              allow 172.16.25.0/24;
              allow 192.168.1.0/24;
              allow 10.10.10.0/24;
              deny all;
            '';
          };
          ${feedsHostname} = {
            forceSSL = true;
            useACMEHost = certificateName;
            extraConfig = ''
              add_header X-Content-Type-Options "nosniff" always;
              add_header Referrer-Policy "same-origin" always;
              add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
              allow 172.16.25.0/24;
              allow 192.168.1.0/24;
              allow 10.10.10.0/24;
              deny all;
            '';
            locations."/" = {
              proxyPass = "http://127.0.0.1:8081";
              proxyWebsockets = true;
            };
          };
        };
      };

      systemd.services.nginx = {
        after = [
          "miniflux.service"
          "uwsgi.service"
        ];
        wants = [
          "miniflux.service"
          "uwsgi.service"
        ];
      };
    };
}
