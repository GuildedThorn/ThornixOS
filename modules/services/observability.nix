{ inputs, ... }:
{
  nixos.modules.services-observability =
    {
      config,
      lib,
      pkgs,
      ...
    }:

    let
      cfg = config.thorn.telemetry;
      alloyConfigPath = toString config.services.alloy.configPath;
      alloyValidationPath =
        if lib.hasPrefix "/etc/" alloyConfigPath then
          "${config.system.build.etc}${alloyConfigPath}"
        else
          alloyConfigPath;
      alloyConfigCheck = pkgs.runCommand "alloy-config-check-${config.networking.hostName}" { } ''
        echo "validating assembled Alloy configuration at ${alloyValidationPath}"
        ${lib.getExe config.services.alloy.package} validate ${alloyValidationPath}
        touch "$out"
      '';
      # nginx terminates ThornCloud_CA mTLS on soc. Loki itself is bound to
      # loopback, so this is the only network path into its write API.
      lokiUrl = "https://soc.guildedthorn.arpa:3100";
      telemetryCredentialDirectory = "/run/credentials/alloy.service";
      telemetryWriterCertificate = "${inputs.self}/certs/telemetry-writer.crt";
      telemetryWriterSecrets = "${inputs.self}/hosts/shared/telemetry-secrets.yaml";
      nodeTextfileDirectory = "/var/lib/node-exporter-textfiles";
    in
    {
      options.thorn.telemetry.enable = lib.mkEnableOption "authenticated fleet telemetry shipping";

      config = lib.mkMerge [
        {
          # Node metrics for Prometheus on soc. Do not use the exporter's
          # broad openFirewall switch: the explicit rule below admits only
          # the SOC VM.
          services.prometheus.exporters.node = {
            enable = true;
            enabledCollectors = [
              "systemd"
              "textfile"
            ];
            # Multiple textfile directories are supported. Zeek adds its
            # fast-changing runtime directory on mac, while durable success
            # proofs written here survive reboots on every fleet host.
            extraFlags = [ "--collector.textfile.directory=${nodeTextfileDirectory}" ];
            openFirewall = false;
          };

          systemd.tmpfiles.rules = [
            "d ${nodeTextfileDirectory} 0755 root root -"
            "d /var/lib/thorn-backup 0700 root root -"
          ];

          # comin's metrics endpoint is similarly visible only to the SOC.
          # Loopback remains available for scout's local Alloy scrape.
          networking.firewall.extraCommands = ''
            iptables -w -A nixos-fw -p tcp -s 172.16.25.51/32 \
              -m multiport --dports 9100,4243 -j nixos-fw-accept
          '';
        }

        # A NixOS closure build normally validates only the Nix expression;
        # embedded Alloy syntax and component selectors are parsed at runtime.
        # Make the ordinary per-host CI build depend on validation of the exact
        # assembled /etc/alloy directory so an invalid config never reaches
        # production. Validating the directory also catches duplicate or
        # broken cross-file component references.
        (lib.mkIf config.services.alloy.enable {
          system.checks = [ alloyConfigCheck ];
        })

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = builtins.pathExists telemetryWriterCertificate;
              message = ''
                certs/telemetry-writer.crt is missing. Sign the fleet writer
                CSR with ThornCloud_CA before enabling telemetry.
              '';
            }
            {
              assertion = builtins.pathExists telemetryWriterSecrets;
              message = ''
                hosts/shared/telemetry-secrets.yaml is missing. Create it
                with sops and add telemetry_writer_key before enabling telemetry.
              '';
            }
          ];

          # One write-only client identity is shared by the enrolled fleet.
          # systemd exposes it only inside Alloy's credential directory.
          sops.secrets.telemetry_writer_key = {
            sopsFile = telemetryWriterSecrets;
            restartUnits = [ "alloy.service" ];
          };

          services.alloy.enable = true;
          systemd.services.alloy.serviceConfig = {
            SupplementaryGroups = [ "systemd-journal" ];
            LoadCredential = [
              "telemetry-writer.crt:${telemetryWriterCertificate}"
              "telemetry-writer.key:${config.sops.secrets.telemetry_writer_key.path}"
            ];
          };

          environment.etc."alloy/config.alloy".text = ''
            loki.relabel "journal" {
              forward_to = []

              rule {
                source_labels = ["__journal__systemd_unit"]
                target_label  = "unit"
              }
              rule {
                source_labels = ["__journal__hostname"]
                target_label  = "host"
              }
            }

            loki.source.journal "journal" {
              forward_to    = [loki.write.soc.receiver]
              relabel_rules = loki.relabel.journal.rules
              labels        = { job = "systemd-journal" }
              max_age       = "24h"
            }

            loki.write "soc" {
              endpoint {
                url = "${lokiUrl}/loki/api/v1/push"

                tls_config {
                  ca_file     = "${config.security.pki.caBundle}"
                  cert_file   = "${telemetryCredentialDirectory}/telemetry-writer.crt"
                  key_file    = "${telemetryCredentialDirectory}/telemetry-writer.key"
                  server_name = "soc.guildedthorn.arpa"
                  min_version = "TLS12"
                }
              }
            }
          '';
        })
      ];
    };
}
