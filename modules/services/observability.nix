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

      # comin's metrics endpoint. comin already listens on 0.0.0.0:4243 on
      # every host (it's on by default); this only opens the port so soc can
      # scrape it.
      #
      # Worth the exposure because it closes the fleet's one structural
      # monitoring gap: everything else here reports whether a host is alive
      # and talking, but nothing reports whether it is running the config
      # that was pushed. comin_deployment_info carries the deployed commit
      # id, so "did my change actually land" becomes a query instead of an
      # SSH session. On a repo whose entire deployment model is GitOps, that
      # is the layer most worth seeing.
      #
      # Same trust assumption 9100 already makes: LAN-reachable, unauthenticated,
      # read-only. It exposes commit ids and deploy/build/eval status — no
      # secrets, but it does tell a LAN observer exactly what version each
      # host runs.
      networking.firewall.allowedTCPPorts = [ 4243 ];
    };
}
