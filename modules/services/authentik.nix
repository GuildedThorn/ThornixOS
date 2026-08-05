{
  nixos.modules.services-authentik =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      authentikStateDirectory = "/var/lib/authentik";
      authentikSecretKey = "${authentikStateDirectory}/secret-key";

      # This pinned nixpkgs revision has stale distribution metadata in
      # django-postgres-extra and django-tenants, plus incorrect versions on
      # Authentik's bundled workspace packages. Authentik builds a private
      # Python package set, so wrap only the interpreter passed to Authentik
      # and compose these fixes with Authentik's own package overrides. The
      # fail-fast replacements keep metadata checks enabled and make a future
      # source change tell us when this workaround is obsolete.
      authentikPython = pkgs.python314 // {
        override =
          arguments:
          pkgs.python314.override (
            arguments
            // {
              packageOverrides = lib.composeExtensions (arguments.packageOverrides or (_: _: { })) (
                _final: previous: {
                  django-postgres-extra = previous.django-postgres-extra.overridePythonAttrs (old: {
                    postPatch = (old.postPatch or "") + ''
                      substituteInPlace psqlextra/_version.py \
                        --replace-fail '__version__ = "2.0.9rc4"' '__version__ = "${old.version}"'
                    '';
                  });
                  django-tenants = previous.django-tenants.overridePythonAttrs (old: {
                    postPatch = (old.postPatch or "") + ''
                      substituteInPlace pyproject.toml \
                        --replace-fail 'version = "3.10.2"' 'version = "${old.version}"'
                    '';
                  });

                  # The bundled workspace packages have their own versions;
                  # nixpkgs incorrectly assigns Authentik's release version to
                  # all four. Preserve the versions declared by their own
                  # pyproject.toml files and Authentik's dependency metadata.
                  ak-guardian = previous.ak-guardian.overridePythonAttrs (_: {
                    version = "3.2.0";
                  });
                  django-channels-postgres = previous.django-channels-postgres.overridePythonAttrs (_: {
                    version = "0.1.0";
                  });
                  django-dramatiq-postgres = previous.django-dramatiq-postgres.overridePythonAttrs (_: {
                    version = "0.1.0";
                  });
                  django-postgres-cache = previous.django-postgres-cache.overridePythonAttrs (_: {
                    version = "0.1.0";
                  });

                  # This attribute is named authentik-django inside nixpkgs to
                  # distinguish it from the final wrapper, but the Python
                  # distribution itself is correctly named "authentik".
                  authentik-django = previous.authentik-django.overridePythonAttrs (_: {
                    pname = "authentik";
                  });
                }
              );
            }
          );
      };
      authentikPackage = pkgs.authentik.override { python314 = authentikPython; };

      # Keep every non-secret setting declarative. The installation secret is
      # deliberately read from a persistent service-owned file instead of
      # being copied into the Nix store. A first-boot oneshot below creates it
      # before authentik starts, avoiding an SOPS bootstrap loop on a brand-new
      # VM whose SSH host key (and therefore age recipient) does not exist yet.
      authentikConfig = pkgs.writeText "authentik.yml" ''
        secret_key: file://${authentikSecretKey}

        postgresql:
          host: /run/postgresql
          port: 5432
          name: authentik
          user: authentik
          password: ""
          sslmode: disable

        listen:
          # Cleartext traffic never leaves loopback. The native HTTPS listener
          # supplies a generated certificate until ThornCloud_CA enrollment.
          http:
            - "127.0.0.1:9000"
          https:
            - "0.0.0.0:443"
          metrics:
            - "0.0.0.0:9300"
          debug: "127.0.0.1:9900"
          debug_py: "127.0.0.1:9901"
          debug_tokio: "127.0.0.1:6669"
          trusted_proxy_cidrs:
            - "127.0.0.0/8"
            - "::1/128"

        storage:
          backend: file
          file:
            path: ${authentikStateDirectory}/data

        cert_discovery_dir: ${authentikStateDirectory}/certs

        # Updates are delivered by the pinned nixpkgs input and comin. Avoid
        # an independent update channel and disable startup telemetry.
        disable_update_check: true
        disable_startup_analytics: true
        error_reporting:
          enabled: false

        # There is intentionally no Docker socket on this identity server.
        # The embedded outpost remains available for future proxy providers,
        # while automatic discovery of external container outposts is off.
        outposts:
          discover: false
          disable_embedded_outpost: false
      '';

      createSecretKey = pkgs.writeShellScript "authentik-create-secret-key" ''
        set -euo pipefail

        secret=${lib.escapeShellArg authentikSecretKey}
        if [[ ! -s "$secret" ]]; then
          temporary="$secret.tmp"
          ${lib.getExe pkgs.openssl} rand -base64 60 \
            | ${pkgs.coreutils}/bin/tr -d '\n' > "$temporary"
          chmod 0400 "$temporary"
          mv "$temporary" "$secret"
        fi
      '';
    in
    {
      users.groups.authentik = { };
      users.users.authentik = {
        isSystemUser = true;
        group = "authentik";
        home = authentikStateDirectory;
        description = "authentik identity provider";
      };

      environment.systemPackages = [ authentikPackage ];
      environment.etc."authentik/config.yml".source = authentikConfig;
      systemd.tmpfiles.rules = [
        "d ${authentikStateDirectory}/data 0700 authentik authentik -"
        "d ${authentikStateDirectory}/certs 0700 authentik authentik -"
      ];

      # PostgreSQL stays on a Unix socket. Peer authentication binds the
      # authentik database role to the equally named system account, so no
      # reusable database password exists to leak or rotate.
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_16;
        ensureDatabases = [ "authentik" ];
        ensureUsers = [
          {
            name = "authentik";
            ensureDBOwnership = true;
          }
        ];
        settings = {
          listen_addresses = lib.mkForce "";
          password_encryption = "scram-sha-256";
        };
      };

      # This is only a same-disk logical safety net for a bad migration or
      # accidental database change. It does not replace the deferred off-host
      # Proxmox/PBS backup project.
      services.postgresqlBackup = {
        enable = true;
        databases = [ "authentik" ];
        startAt = "*-*-* 02:15:00";
        compression = "zstd";
      };

      systemd.services.authentik-secret-key = {
        description = "Create authentik installation secret";
        before = [ "authentik.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "authentik";
          Group = "authentik";
          StateDirectory = "authentik";
          StateDirectoryMode = "0700";
          UMask = "0077";
          ExecStart = createSecretKey;
          RemainAfterExit = true;
        };
      };

      # nixpkgs packages the exact Authentik version pinned by this flake.
      # `allinone` runs the web server and background worker together, which
      # is the upstream-supported small-deployment mode; the worker performs
      # schema migrations before reporting ready.
      systemd.services.authentik = {
        description = "authentik identity provider";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "authentik-secret-key.service"
          "postgresql.target"
        ];
        after = [
          "authentik-secret-key.service"
          "network-online.target"
          "postgresql.target"
        ];
        wants = [ "network-online.target" ];
        restartTriggers = [ authentikConfig ];

        environment = {
          HOME = authentikStateDirectory;
          SSL_CERT_FILE = config.security.pki.caBundle;
          REQUESTS_CA_BUNDLE = config.security.pki.caBundle;
        };

        serviceConfig = {
          Type = "simple";
          User = "authentik";
          Group = "authentik";
          StateDirectory = "authentik";
          StateDirectoryMode = "0700";
          WorkingDirectory = authentikStateDirectory;
          ExecStart = "${lib.getExe authentikPackage} allinone";
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStartSec = "15min";
          TimeoutStopSec = "10min";
          UMask = "0077";

          # Port 443 is the sole privileged operation. Everything else runs
          # as the dedicated service account with a read-only system image.
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
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
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };
    };
}
