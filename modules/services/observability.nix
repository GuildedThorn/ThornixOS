{
  nixos.modules.services-observability =
    { ... }:

    let
      # Loki on the soc VM — every host ships its journal here.
      lokiUrl = "http://soc.guildedthorn.arpa:3100";
    in
    {
      # Grafana Alloy: tail the systemd journal and push it to Loki on soc.
      # If soc is unreachable Alloy buffers and retries; nothing on the host
      # breaks, logs just arrive late.
      services.alloy.enable = true;

      # Alloy runs with DynamicUser and can't read the journal without this.
      systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];

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
          }
        }
      '';

      # Node metrics for Prometheus on soc. 9100 is only exposed on the LAN;
      # nothing routes it further.
      services.prometheus.exporters.node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
        openFirewall = true;
      };
    };
}
