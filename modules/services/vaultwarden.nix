{ inputs, ... }:
{
  nixos.modules.services-vaultwarden =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "vault.guildedthorn.arpa";
      stateDirectory = "/var/lib/vaultwarden";
      adminTokenPath = "${stateDirectory}/initial-admin-token";
      adminEnvironmentPath = "${stateDirectory}/admin.env";
      backupReady = builtins.pathExists "${inputs.self}/hosts/vault/backup-secrets.yaml";

      createAdminToken = pkgs.writeShellScript "vaultwarden-create-admin-token" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        token_path=${lib.escapeShellArg adminTokenPath}
        environment_path=${lib.escapeShellArg adminEnvironmentPath}

        if [[ ! -s "$token_path" ]]; then
          ${pkgs.openssl}/bin/openssl rand -base64 48 \
            | ${pkgs.coreutils}/bin/tr -d '\n' > "$token_path.new"
          printf '\n' >> "$token_path.new"
          chmod 0400 "$token_path.new"
          mv -T "$token_path.new" "$token_path"
        fi

        if [[ ! -s "$environment_path" ]]; then
          salt=$(${pkgs.openssl}/bin/openssl rand -hex 16)
          token_hash=$(
            ${pkgs.coreutils}/bin/tr -d '\n' < "$token_path" \
              | ${lib.getExe pkgs.libargon2} "$salt" \
                  -id -k 65540 -t 3 -p 4 -l 32 -e
          )
          printf "ADMIN_TOKEN='%s'\n" "$token_hash" > "$environment_path.new"
          chmod 0400 "$environment_path.new"
          mv -T "$environment_path.new" "$environment_path"
          unset salt token_hash
        fi
      '';

      showAdminToken = pkgs.writeShellApplication {
        name = "vault-admin-token";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if [[ $EUID -ne 0 ]]; then
            echo "error: run vault-admin-token as root" >&2
            exit 1
          fi
          if [[ ! -s ${lib.escapeShellArg adminTokenPath} ]]; then
            echo "error: Vaultwarden has not generated its administrator token" >&2
            exit 1
          fi
          tr -d '\n' < ${lib.escapeShellArg adminTokenPath}
          printf '\n'
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "vault";
          message = "services-vaultwarden is a fixed service profile for the vault host";
        }
      ];

      services.vaultwarden = {
        enable = true;
        dbBackend = "sqlite";
        environmentFile = adminEnvironmentPath;
        config = {
          DOMAIN = "https://${hostname}";
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = 8222;
          SIGNUPS_ALLOWED = false;
          INVITATIONS_ALLOWED = true;
          PASSWORD_HINTS_ALLOWED = false;
          SHOW_PASSWORD_HINT = false;
          HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS = true;
          WEB_VAULT_ENABLED = true;
        };
      };

      systemd.services.vaultwarden-admin-token = {
        description = "Create Vaultwarden's installation-specific administrator token";
        requiredBy = [ "vaultwarden.service" ];
        before = [ "vaultwarden.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "vaultwarden";
          Group = "vaultwarden";
          StateDirectory = "vaultwarden";
          StateDirectoryMode = "0700";
          UMask = "0077";
          ExecStart = createAdminToken;
          RemainAfterExit = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ stateDirectory ];
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
            add_header Referrer-Policy "same-origin" always;
            client_max_body_size 128m;
          '';
          locations = {
            "/" = {
              proxyPass = "http://127.0.0.1:8222";
              proxyWebsockets = true;
            };
            "^~ /admin" = {
              proxyPass = "http://127.0.0.1:8222";
              extraConfig = ''
                allow 172.16.25.3;
                allow 192.168.1.6;
                allow 192.168.1.74;
                allow 10.10.10.4;
                deny all;
              '';
            };
          };
        };
      };

      systemd.services.nginx = {
        wants = [ "vaultwarden.service" ];
        after = [ "vaultwarden.service" ];
      };

      environment.systemPackages = [ showAdminToken ];

      thorn.backup = lib.mkIf backupReady {
        enable = true;
        schedule = "*-*-* 03:50:00";
        paths = [ stateDirectory ];
        quiesceServices = [ "vaultwarden.service" ];
        restorePaths = [ "${stateDirectory}/db.sqlite3" ];
        restoreValidationCommand = ''
          ${pkgs.sqlite}/bin/sqlite3 \
            "$RESTORE_ROOT${stateDirectory}/db.sqlite3" \
            'PRAGMA integrity_check;' \
            | ${pkgs.gnugrep}/bin/grep --fixed-strings --line-regexp ok >/dev/null
        '';
      };
    };
}
