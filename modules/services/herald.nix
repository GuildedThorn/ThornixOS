{ inputs, ... }:
{
  nixos.modules.services-herald =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "herald.guildedthorn.arpa";
      stateDirectory = "/var/lib/ntfy-sh";
      initialPasswordPath = "${stateDirectory}/initial-admin-password";
      relayEnvironmentPath = "${stateDirectory}/courier-relay.env";

      createInitialAdmin = pkgs.writeShellScript "herald-create-initial-admin" ''
        set -o errexit -o nounset -o pipefail
        umask 0077

        password_path=${lib.escapeShellArg initialPasswordPath}
        if [[ ! -s "$password_path" ]]; then
          ${pkgs.openssl}/bin/openssl rand -base64 36 \
            | ${pkgs.coreutils}/bin/tr -d '\n' > "$password_path.new"
          printf '\n' >> "$password_path.new"
          chmod 0400 "$password_path.new"
          mv -T "$password_path.new" "$password_path"
        fi

        # ntfy creates the SQLite auth database during server startup. The
        # CLI's idempotent flag preserves any password or role changed later.
        export NTFY_PASSWORD
        NTFY_PASSWORD=$(${pkgs.coreutils}/bin/tr -d '\n' < "$password_path")
        ${lib.getExe pkgs.ntfy-sh} user add \
          --ignore-exists --role=admin thorn
      '';

      showInitialPassword = pkgs.writeShellApplication {
        name = "herald-initial-password";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if [[ $EUID -ne 0 ]]; then
            echo "error: run herald-initial-password as root" >&2
            exit 1
          fi
          if [[ ! -s ${lib.escapeShellArg initialPasswordPath} ]]; then
            echo "error: Herald has not generated its initial administrator yet" >&2
            exit 1
          fi
          printf 'username: thorn\npassword: '
          tr -d '\n' < ${lib.escapeShellArg initialPasswordPath}
          printf '\n'
        '';
      };

      configureCourierRelay = pkgs.writeShellApplication {
        name = "herald-configure-courier-relay";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.openssl
          pkgs.systemd
        ];
        text = ''
          set -o errexit -o nounset -o pipefail
          if [[ $EUID -ne 0 ]]; then
            echo "error: run herald-configure-courier-relay as root" >&2
            exit 1
          fi

          echo "Courier must have a STARTTLS submission listener on port 587 and a dedicated Herald account."
          read -r -p "Courier SMTP username: " smtp_user
          read -r -p "Envelope/from address: " smtp_from
          read -r -s -p "Courier SMTP password: " smtp_password
          printf '\n'
          [[ -n "$smtp_user" && -n "$smtp_from" && -n "$smtp_password" ]] || {
            echo "error: username, from address, and password are required" >&2
            exit 1
          }
          if [[ ! "$smtp_user" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
            echo "error: Courier SMTP username must be a full e-mail address" >&2
            exit 1
          fi
          if [[ ! "$smtp_from" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
            echo "error: envelope/from must be a full e-mail address" >&2
            exit 1
          fi

          # Prove both the ThornCloud certificate and supplied credentials
          # before replacing the last known relay configuration. AUTH PLAIN is
          # carried only inside the verified TLS session, and the secret never
          # appears in a process argument or command output.
          auth_payload=$(printf '\0%s\0%s' "$smtp_user" "$smtp_password" | base64 -w0)
          smtp_response=$(
            {
              printf 'AUTH PLAIN %s\r\n' "$auth_payload"
              printf 'QUIT\r\n'
            } | timeout 15 openssl s_client \
              -quiet \
              -verify_return_error \
              -CAfile ${lib.escapeShellArg config.security.pki.caBundle} \
              -servername courier.guildedthorn.arpa \
              -connect courier.guildedthorn.arpa:587 \
              -starttls smtp 2>&1 || true
          )
          unset auth_payload
          if ! printf '%s\n' "$smtp_response" | grep -q '^235 '; then
            unset smtp_response smtp_password
            echo "error: Courier rejected the credentials or STARTTLS verification failed" >&2
            exit 1
          fi
          unset smtp_response

          escape_environment_value() {
            printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
          }

          relay_path=${lib.escapeShellArg relayEnvironmentPath}
          relay_tmp=$(mktemp "${stateDirectory}/.courier-relay.XXXXXX")
          trap 'rm -f "$relay_tmp"' EXIT
          {
            printf 'NTFY_SMTP_SENDER_ADDR="courier.guildedthorn.arpa:587"\n'
            printf 'NTFY_SMTP_SENDER_USER="%s"\n' "$(escape_environment_value "$smtp_user")"
            printf 'NTFY_SMTP_SENDER_PASS="%s"\n' "$(escape_environment_value "$smtp_password")"
            printf 'NTFY_SMTP_SENDER_FROM="%s"\n' "$(escape_environment_value "$smtp_from")"
            printf 'NTFY_SMTP_SENDER_VERIFY="true"\n'
          } > "$relay_tmp"
          chown ntfy-sh:ntfy-sh "$relay_tmp"
          chmod 0600 "$relay_tmp"
          mv -T "$relay_tmp" "$relay_path"
          trap - EXIT
          systemctl restart ntfy-sh.service
          echo "Herald now sends requested e-mail notifications through Courier."
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.networking.hostName == "herald";
          message = "services-herald is a fixed service profile for the herald host";
        }
      ];

      services.ntfy-sh = {
        enable = true;
        environmentFile = relayEnvironmentPath;
        settings = {
          base-url = "https://${hostname}";
          listen-http = "127.0.0.1:2586";
          behind-proxy = true;
          proxy-forwarded-header = "X-Forwarded-For";
          proxy-trusted-hosts = "127.0.0.1";

          # This is a private notification plane. Accounts are created only
          # by an administrator, and unknown callers cannot read or publish.
          auth-default-access = "deny-all";
          enable-login = true;
          enable-signup = false;
          enable-reservations = true;
          require-login = true;

          cache-duration = "7d";
          attachment-total-size-limit = "5G";
          attachment-file-size-limit = "20M";
          attachment-expiry-duration = "24h";

          # Mail from legacy/internal applications becomes a push message.
          # The firewall supplies the source boundary; protected topics also
          # require their ntfy token in the recipient address.
          smtp-server-listen = "172.16.25.63:25";
          smtp-server-domain = hostname;
          smtp-server-addr-prefix = "ntfy-";

          metrics-listen-http = "127.0.0.1:9090";
          log-format = "json";
          log-level = "info";
        };
      };

      systemd.tmpfiles.rules = [
        "d ${stateDirectory} 0700 ntfy-sh ntfy-sh -"
        "f ${relayEnvironmentPath} 0600 ntfy-sh ntfy-sh -"
      ];

      systemd.services.herald-ntfy-admin = {
        description = "Create Herald's installation-specific ntfy administrator";
        wantedBy = [ "multi-user.target" ];
        requires = [ "ntfy-sh.service" ];
        after = [ "ntfy-sh.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "ntfy-sh";
          Group = "ntfy-sh";
          StateDirectory = "ntfy-sh";
          StateDirectoryMode = "0700";
          UMask = "0077";
          ExecStart = createInitialAdmin;
          RemainAfterExit = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ stateDirectory ];
        };
      };

      systemd.services.ntfy-sh = {
        serviceConfig = {
          StateDirectoryMode = "0700";
          UMask = "0077";
          ProtectClock = true;
          ProtectHostname = true;
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
            client_max_body_size 20m;
          '';
          locations = {
            "= /metrics" = {
              proxyPass = "http://127.0.0.1:9090/metrics";
              extraConfig = ''
                allow 172.16.25.51;
                deny all;
              '';
            };
            "/" = {
              proxyPass = "http://127.0.0.1:2586";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_buffering off;
                proxy_request_buffering off;
                proxy_read_timeout 90s;
              '';
            };
          };
        };
      };

      systemd.services.nginx = {
        wants = [ "ntfy-sh.service" ];
        after = [ "ntfy-sh.service" ];
      };

      environment.systemPackages = [
        pkgs.ntfy-sh
        showInitialPassword
        configureCourierRelay
      ];
    };
}
