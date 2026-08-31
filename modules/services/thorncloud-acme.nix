{ inputs, ... }:
{
  nixos.modules.services-thorncloud-acme =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.acme;
      rootCertificate = "${inputs.self}/certs/ThornCloud_CA.crt";
      certificateDirectory = "/var/lib/acme/${cfg.domain}";
      bootstrapConfigured = cfg.bootstrapCertificate != null && cfg.bootstrapKey != null;
    in
    {
      options.thorn.acme = {
        enable = lib.mkEnableOption "automatic certificates from the ThornCloud internal ACME service";

        domain = lib.mkOption {
          type = lib.types.str;
          default = config.networking.fqdn;
          defaultText = lib.literalExpression "config.networking.fqdn";
          description = "Primary internal DNS name to place on the certificate.";
        };

        extraDomainNames = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional internal DNS names to place on the certificate.";
        };

        email = lib.mkOption {
          type = lib.types.str;
          default = "admin@guildedthorn.com";
          description = "Contact attached to the internal ACME account.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "nginx";
          description = "Group allowed to read the issued private key.";
        };

        reloadServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "nginx.service" ];
          description = "Services reloaded after a successful issuance or renewal.";
        };

        # These two options are only for the first migration. They let nginx
        # continue serving the existing trusted certificate while the first
        # ACME order is in flight. Once a renewal has been observed, callers
        # can remove them together with the old SOPS key.
        bootstrapCertificate = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Existing certificate used until the first ACME order succeeds.";
        };

        bootstrapKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Runtime path to the existing private key used during migration.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = lib.hasSuffix ".guildedthorn.arpa" cfg.domain;
              message = "thorn.acme.domain must be an internal *.guildedthorn.arpa name";
            }
            {
              assertion = (cfg.bootstrapCertificate == null) == (cfg.bootstrapKey == null);
              message = "thorn.acme bootstrapCertificate and bootstrapKey must be configured together";
            }
          ];

          security.acme = {
            acceptTerms = true;
            defaults = {
              email = cfg.email;
              keyType = "ec256";
              renewInterval = "hourly";
              renewJitter = "15m";
              server = "https://anvil.guildedthorn.arpa/acme/thorncloud/directory";
            };
            certs.${cfg.domain} = {
              extraDomainNames = cfg.extraDomainNames;
              group = cfg.group;
              reloadServices = cfg.reloadServices;
              webroot = "/var/lib/acme/acme-challenge";
            };
          };

          # HTTP-01 needs plaintext port 80, but only the CA performs the
          # validation. Keep it closed to every other routed source.
          networking.firewall.extraCommands = ''
            iptables -w -A nixos-fw -p tcp --dport 80 -s 172.16.25.55/32 -j nixos-fw-accept
          '';

          # NixOS normally permits a day's timer coalescing, which is suitable
          # for 90-day public certificates but unsafe for Anvil's 24-hour
          # leaves. Check hourly with only a five-minute scheduling window.
          systemd.timers."acme-renew-${cfg.domain}".timerConfig.AccuracySec = lib.mkForce "5m";
        })

        (lib.mkIf (cfg.enable && bootstrapConfigured) {
          # switch-to-configuration restarts changed services before it starts
          # newly introduced units. Seed during activation, after sops-nix has
          # materialized the legacy key, so nginx's preflight always sees a
          # complete certificate set on the very first migration.
          system.activationScripts.thorncloudAcmeBootstrap = {
            deps = [ "setupSecrets" ];
            text = ''
              set -eu

              certificate_directory=${lib.escapeShellArg certificateDirectory}
              if [ ! -e "$certificate_directory/acme-success" ]; then
                ${pkgs.coreutils}/bin/install -d -m 0750 -o acme -g ${lib.escapeShellArg cfg.group} \
                  "$certificate_directory"
                ${pkgs.coreutils}/bin/install -m 0640 -o acme -g ${lib.escapeShellArg cfg.group} \
                  ${lib.escapeShellArg (toString cfg.bootstrapCertificate)} \
                  "$certificate_directory/fullchain.pem"
                ${pkgs.coreutils}/bin/install -m 0640 -o acme -g ${lib.escapeShellArg cfg.group} \
                  ${lib.escapeShellArg cfg.bootstrapKey} \
                  "$certificate_directory/key.pem"
                ${pkgs.coreutils}/bin/install -m 0640 -o acme -g ${lib.escapeShellArg cfg.group} \
                  ${lib.escapeShellArg rootCertificate} \
                  "$certificate_directory/chain.pem"
                ${pkgs.coreutils}/bin/touch "$certificate_directory/acme-success"
                ${pkgs.coreutils}/bin/chown acme:${lib.escapeShellArg cfg.group} \
                  "$certificate_directory/acme-success"
              fi
            '';
          };
        })
      ];
    };
}
