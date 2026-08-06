{ inputs, ... }:
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
      tlsCertificate = "${inputs.self}/certs/atlas.guildedthorn.arpa.crt";
      tlsKey = config.sops.secrets.netbox_tls_key.path;
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

          # NetBox's application metrics are enabled, but only the SOC may
          # read them through this authenticated ThornCloud_CA endpoint.
          locations."= /metrics" = {
            proxyPass = "http://${config.services.netbox.bind}";
            extraConfig = ''
              allow 172.16.25.51;
              deny all;
            '';
          };
        };
      };

      systemd.services.nginx = {
        after = [ "netbox.service" ];
        wants = [ "netbox.service" ];
      };
    };
}
