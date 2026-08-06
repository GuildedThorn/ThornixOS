{
  nixos.modules.services-netbox =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostname = "atlas.guildedthorn.arpa";
      address = "172.16.25.54";
      tlsDirectory = "/var/lib/atlas-tls";
      tlsCertificate = "${tlsDirectory}/cert.pem";
      tlsKey = "${tlsDirectory}/key.pem";
    in
    {
      services.netbox = {
        enable = true;
        # The fleet keeps stateVersion at its original 25.05 value, which
        # makes the upstream module default to the now-EOL NetBox 4.4 line.
        # Select the supported package explicitly instead of permitting an
        # insecure package or changing state compatibility globally.
        package = pkgs.netbox_4_5;
        nginx = {
          enable = true;
          inherit hostname;
        };
        gunicorn.extraArgs.workers = "3";

        # NetBox, PostgreSQL, and Redis communicate only over local Unix
        # sockets. The NixOS module generates NetBox's installation secret
        # and API-token pepper directly in /var/lib/netbox on first boot, so
        # neither secret is evaluated into the Nix store.
        settings = {
          ALLOWED_HOSTS = [
            hostname
            address
          ];
          BANNER_TOP = "GuildedThorn Atlas - authoritative infrastructure inventory";
          CENSUS_REPORTING_ENABLED = false;
          CSRF_COOKIE_SECURE = true;
          LOGIN_REQUIRED = true;
          METRICS_ENABLED = true;
          RELEASE_CHECK_URL = null;
          SECURE_PROXY_SSL_HEADER = [
            "HTTP_X_FORWARDED_PROTO"
            "https"
          ];
          SECURE_SSL_REDIRECT = true;
          SESSION_COOKIE_SECURE = true;
          TIME_ZONE = "America/Chicago";
        };
      };

      services.postgresql = {
        package = pkgs.postgresql_16;
        settings = {
          listen_addresses = lib.mkForce "";
          password_encryption = "scram-sha-256";
        };
      };

      # This local logical backup protects against a bad migration or an
      # accidental database edit. The authoritative inventory still belongs
      # on NAS-backed/off-host storage once that policy is introduced.
      services.postgresqlBackup = {
        enable = true;
        databases = [ "netbox" ];
        startAt = "*-*-* 02:30:00";
        compression = "zstd";
      };

      services.nginx = {
        recommendedGzipSettings = true;
        recommendedTlsSettings = true;
        virtualHosts.${hostname} = {
          serverName = hostname;
          forceSSL = true;
          sslCertificate = tlsCertificate;
          sslCertificateKey = tlsKey;
          extraConfig = ''
            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "same-origin" always;
            add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
          '';

          # NetBox's application metrics are enabled now, but only the SOC
          # may read them. A Prometheus scrape is added after Atlas receives
          # its ThornCloud_CA leaf; until then, monitoring never needs to
          # disable certificate verification for the bootstrap certificate.
          locations."= /metrics" = {
            proxyPass = "http://${config.services.netbox.bind}";
            extraConfig = ''
              allow 172.16.25.51;
              deny all;
            '';
          };
        };
      };

      # Atlas cannot have a SOPS recipient until its first boot creates an SSH
      # host key. Generate a temporary leaf locally so the first admin password
      # never traverses cleartext HTTP. This service deliberately leaves an
      # existing keypair untouched; enrollment later replaces it with the
      # ThornCloud_CA certificate and a SOPS-managed private key.
      systemd.services.atlas-bootstrap-tls = {
        description = "Create the temporary Atlas HTTPS certificate";
        before = [ "nginx.service" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "atlas-tls";
          StateDirectoryMode = "0750";
          UMask = "0077";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail

          state=${lib.escapeShellArg tlsDirectory}
          key=${lib.escapeShellArg tlsKey}
          certificate=${lib.escapeShellArg tlsCertificate}

          ${pkgs.coreutils}/bin/chown root:nginx "$state"
          ${pkgs.coreutils}/bin/chmod 0750 "$state"

          if [[ -s "$key" && -s "$certificate" ]]; then
            ${pkgs.coreutils}/bin/chown root:nginx "$key" "$certificate"
            ${pkgs.coreutils}/bin/chmod 0440 "$key"
            ${pkgs.coreutils}/bin/chmod 0444 "$certificate"
            exit 0
          fi

          temporary_key="$state/.key.pem.tmp"
          temporary_certificate="$state/.cert.pem.tmp"
          trap '${pkgs.coreutils}/bin/rm -f "$temporary_key" "$temporary_certificate"' EXIT

          ${lib.getExe pkgs.openssl} req \
            -x509 \
            -newkey rsa:3072 \
            -sha256 \
            -nodes \
            -days 365 \
            -subj ${lib.escapeShellArg "/CN=${hostname}"} \
            -addext ${lib.escapeShellArg "subjectAltName=DNS:${hostname},IP:${address}"} \
            -addext ${lib.escapeShellArg "basicConstraints=critical,CA:FALSE"} \
            -addext ${lib.escapeShellArg "keyUsage=critical,digitalSignature,keyEncipherment"} \
            -addext ${lib.escapeShellArg "extendedKeyUsage=serverAuth"} \
            -keyout "$temporary_key" \
            -out "$temporary_certificate"

          ${pkgs.coreutils}/bin/chown root:nginx "$temporary_key" "$temporary_certificate"
          ${pkgs.coreutils}/bin/chmod 0440 "$temporary_key"
          ${pkgs.coreutils}/bin/chmod 0444 "$temporary_certificate"
          ${pkgs.coreutils}/bin/mv -f "$temporary_key" "$key"
          ${pkgs.coreutils}/bin/mv -f "$temporary_certificate" "$certificate"
          trap - EXIT
        '';
      };

      systemd.services.nginx = {
        requires = [ "atlas-bootstrap-tls.service" ];
        after = [
          "atlas-bootstrap-tls.service"
          "netbox.service"
        ];
        wants = [ "netbox.service" ];
      };
    };
}
