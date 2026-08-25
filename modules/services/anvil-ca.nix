{ inputs, ... }:
{
  nixos.modules.services-anvil-ca =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      rootCertificate = "${inputs.self}/certs/ThornCloud_CA.crt";
      intermediateCertificate = "${inputs.self}/certs/anvil-intermediate.crt";
      secretsFile = "${inputs.self}/hosts/anvil/secrets.yaml";
      caMaterialReady = builtins.pathExists intermediateCertificate && builtins.pathExists secretsFile;

      chainCheck = pkgs.runCommand "anvil-ca-chain-check" { } ''
        ${lib.getExe pkgs.openssl} verify \
          -CAfile ${rootCertificate} \
          ${intermediateCertificate}

        ${lib.getExe pkgs.openssl} x509 \
          -in ${intermediateCertificate} \
          -checkend 2592000 \
          -noout

        ${lib.getExe pkgs.openssl} x509 \
          -in ${intermediateCertificate} \
          -noout \
          -text \
          | grep -F "CA:TRUE, pathlen:0"

        touch "$out"
      '';
    in
    lib.mkMerge [
      {
        # Keep the public trust anchor and administration client available
        # during the first, secret-free bootstrap as well as normal service.
        security.pki.certificates = [ (builtins.readFile rootCertificate) ];
        environment.systemPackages = [ pkgs.step-cli ];
      }

      (lib.mkIf caMaterialReady {
        # The root private key never belongs on this machine. Anvil holds only
        # a pathLen=0 issuing intermediate whose encrypted PEM and password are
        # materialized by sops-nix into /run/secrets at activation.
        services.step-ca = {
          enable = true;
          address = "0.0.0.0";
          port = 443;
          openFirewall = false;
          intermediatePasswordFile = config.sops.secrets.step_ca_intermediate_password.path;

          settings = {
            dnsNames = [ "anvil.guildedthorn.arpa" ];
            root = rootCertificate;
            crt = intermediateCertificate;
            key = config.sops.secrets.step_ca_intermediate_key.path;

            db = {
              type = "badger";
              dataSource = "/var/lib/step-ca/db";
            };

            logger.format = "json";

            authority = {
              # Remote provisioner administration stays disabled. Changes to
              # issuance policy remain reviewable Nix configuration.
              enableAdmin = false;
              provisioners = [
                {
                  type = "ACME";
                  name = "thorncloud";
                  forceCN = true;
                  challenges = [
                    "http-01"
                    "tls-alpn-01"
                  ];
                  claims = {
                    minTLSCertDuration = "5m";
                    defaultTLSCertDuration = "24h";
                    maxTLSCertDuration = "168h";
                    disableRenewal = false;
                  };
                }
              ];

              # ACME proves control of the requested host, while this policy
              # independently prevents the online intermediate from issuing
              # public names, IP certificates, or literal wildcard certs.
              policy.x509 = {
                allow.dns = [ "*.guildedthorn.arpa" ];
                allowWildcardNames = false;
              };
            };

            tls = {
              minVersion = 1.2;
              maxVersion = 1.3;
              renegotiation = false;
            };
          };
        };

        # Fail CI before deployment if the checked-in public intermediate is
        # not rooted in ThornCloud_CA, expires within 30 days, or can issue a
        # further intermediate.
        system.checks = [ chainCheck ];

        thorn.backup = {
          enable = true;
          schedule = "*-*-* 02:05:00";
          paths = [ "/var/lib/private/step-ca" ];
          quiesceServices = [ "step-ca.service" ];
          restorePaths = [ "/var/lib/private/step-ca/db/MANIFEST" ];
        };

        systemd.services.step-ca.serviceConfig = {
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          RestrictRealtime = true;
        };
      })
    ];
}
