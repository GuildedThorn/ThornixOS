{
  config,
  lib,
  socMonitoring,
  ...
}:
let
  inherit (socMonitoring) securityWorkflowReady;
in
{
  services.grafana.provision = {
    # Deliver alerts to Discord. The webhook URL is read from the
    # sops secret at runtime via $__file{}, so it's never in the
    # Nix store or the repo.
    alerting.contactPoints.settings = {
      apiVersion = 1;
      contactPoints = [
        {
          orgId = 1;
          name = "discord";
          receivers = [
            {
              uid = "discord-siem";
              type = "discord";
              settings.url = "$__file{${config.sops.secrets.grafana_discord_webhook.path}}";
            }
          ];
        }
      ]
      ++ lib.optionals securityWorkflowReady [
        {
          orgId = 1;
          name = "security-casebook";
          receivers = [
            {
              # Preserve the existing page while the same grouped
              # notification is delivered to the incident system.
              uid = "discord-security-casebook";
              type = "discord";
              settings.url = "$__file{${config.sops.secrets.grafana_discord_webhook.path}}";
            }
            {
              uid = "thehive-security-relay";
              type = "webhook";
              disableResolveMessage = true;
              settings = {
                url = "http://127.0.0.1:9088/grafana";
                httpMethod = "POST";
                maxAlerts = "0";
                hmacConfig = {
                  secret = "$__file{${config.sops.secrets.grafana_security_webhook_hmac.path}}";
                  header = "X-Grafana-Alerting-Signature";
                  timestampHeader = "X-Grafana-Alerting-Signature-Timestamp";
                };
              };
            }
          ];
        }
      ];
    };

    # Grafana still evaluates and records audit-stack detections,
    # but this all-week mute keeps them out of Discord and TheHive
    # while their baseline/noise is being reviewed. The matching
    # notification-policy child route is deliberately first and
    # does not continue into any paging route.
    alerting.muteTimings.settings = {
      apiVersion = 1;
      muteTimes = [
        {
          orgId = 1;
          name = "audit-stack-record-only";
          time_intervals = [
            {
              weekdays = [
                "monday"
                "tuesday"
                "wednesday"
                "thursday"
                "friday"
                "saturday"
                "sunday"
              ];
            }
          ];
        }
      ];
    };

    # Route paging rules to Discord, split by the `severity` label
    # the rule helper sets. Audit-stack's `delivery=record-only`
    # rules are intercepted by the permanently-muted first child
    # route: their state remains visible in Grafana, but they cannot
    # reach Discord or the security-case workflow.
    #
    # Group by alertname and host so one flapping host doesn't spam
    # per-series.
    alerting.policies.settings = {
      apiVersion = 1;
      policies = [
        {
          orgId = 1;
          receiver = "discord";
          group_by = [
            "alertname"
            "host"
            "instance"
          ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
          routes = [
            {
              receiver = "discord";
              object_matchers = [
                [
                  "delivery"
                  "="
                  "record-only"
                ]
              ];
              mute_time_intervals = [ "audit-stack-record-only" ];
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "4h";
            }
          ]
          ++ lib.optionals securityWorkflowReady [
            {
              receiver = "security-casebook";
              object_matchers = [
                [
                  "severity"
                  "="
                  "critical"
                ]
                [
                  "category"
                  "="
                  "security"
                ]
              ];
              group_wait = "10s";
              group_interval = "1m";
              repeat_interval = "1h";
            }
          ]
          ++ [
            {
              receiver = "discord";
              object_matchers = [
                [
                  "severity"
                  "="
                  "critical"
                ]
              ]
              ++ lib.optionals securityWorkflowReady [
                [
                  "category"
                  "!="
                  "security"
                ]
              ];
              group_wait = "10s";
              group_interval = "1m";
              # Re-notify hourly rather than 4-hourly: a critical
              # that's still firing is one nobody has actioned yet.
              repeat_interval = "1h";
            }
          ];
        }
      ];
    };

  };
}
