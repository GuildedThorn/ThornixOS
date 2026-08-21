{
  lib,
  socMonitoring,
  ...
}:
let
  inherit (socMonitoring)
    canaryHosts
    cominFetchInstanceRegex
    fleetJournalHosts
    internalAcmeProbeRegex
    lureTelemetryReady
    securityWorkflowReady
    ;
in
{
  services.grafana.provision = {
    # SOC Phase 3: correlation/alerting rules.
    alerting.rules.settings = {
      apiVersion = 1;
      groups = [
        {
          orgId = 1;
          name = "siem";
          folder = "SIEM";
          interval = "1m";
          rules =
            let
              # Instant query (refId A) + threshold expression
              # (refId C) — the shape Grafana's UI itself builds.
              rule =
                {
                  uid,
                  title,
                  datasourceUid,
                  expr,
                  evaluator,
                  for,
                  summary,
                  # "critical" = something is actively hostile or
                  # the SIEM itself is blind; "warning" = degraded,
                  # look when convenient. Drives the notification
                  # policy split below, and is a label you can
                  # filter/silence on in Grafana.
                  severity ? "warning",
                  # Broad routing/search label shared by Discord
                  # notifications and Grafana's alert list.
                  category ? "operations",
                  # Evaluate and retain state/history in Grafana,
                  # but match the permanently-muted policy route.
                  recordOnly ? false,
                  noDataState ? "OK",
                  # Lookback the rule evaluates over, in seconds.
                  # Keep in sync with the range selector in `expr`
                  # for Loki rules — the expression's own `[10m]`
                  # is what actually bounds the count.
                  window ? 600,
                }:
                let
                  # Grafana 13 refuses to threshold a Loki instant
                  # query directly ("looks like time series data,
                  # only reduced data can be alerted on") — every
                  # Loki rule needs an explicit reduce step between
                  # query and threshold. Prometheus instant vectors
                  # are accepted as-is, so those rules keep the
                  # two-node shape.
                  isLoki = datasourceUid == "loki";
                in
                {
                  inherit
                    uid
                    title
                    for
                    noDataState
                    ;
                  condition = "C";
                  execErrState = "Error";
                  annotations = {
                    inherit summary;
                    description = summary;
                  };
                  labels = {
                    inherit severity category;
                  }
                  // lib.optionalAttrs recordOnly {
                    delivery = "record-only";
                  };
                  data = [
                    {
                      refId = "A";
                      inherit datasourceUid;
                      relativeTimeRange = {
                        from = window;
                        to = 0;
                      };
                      model = {
                        refId = "A";
                        inherit expr;
                        instant = true;
                      };
                    }
                  ]
                  ++ (
                    if isLoki then
                      [
                        {
                          refId = "B";
                          datasourceUid = "__expr__";
                          relativeTimeRange = {
                            from = 0;
                            to = 0;
                          };
                          model = {
                            refId = "B";
                            type = "reduce";
                            expression = "A";
                            reducer = "last";
                          };
                        }
                      ]
                    else
                      [ ]
                  )
                  ++ [
                    {
                      refId = "C";
                      datasourceUid = "__expr__";
                      relativeTimeRange = {
                        from = 0;
                        to = 0;
                      };
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = if isLoki then "B" else "A";
                        conditions = [
                          {
                            type = "query";
                            inherit evaluator;
                            operator.type = "and";
                            query.params = [ "C" ];
                            reducer = {
                              type = "last";
                              params = [ ];
                            };
                          }
                        ];
                      };
                    }
                  ];
                };
            in
            [
              (rule {
                uid = "siem-host-down";
                title = "Host down (node exporter unreachable)";
                datasourceUid = "prometheus";
                expr = "up{job=\"node\"}";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "5m";
                noDataState = "NoData";
                summary = "A fleet host has stopped answering Prometheus scrapes.";
              })
              (rule {
                uid = "siem-topology-stale";
                title = "Live network topology is stale";
                datasourceUid = "prometheus";
                expr = "time() - thorn_topology_last_render_timestamp_seconds{job=\"topology\"}";
                evaluator = {
                  type = "gt";
                  params = [ 60 ];
                };
                for = "2m";
                noDataState = "Alerting";
                category = "pipeline";
                summary = "mac's bounded Zeek topology snapshot has not refreshed in 60 seconds; the live graph is stale even if node_exporter itself is still reachable.";
              })
              (rule {
                uid = "siem-topology-input-unavailable";
                title = "Live topology cannot read Zeek conn.log";
                datasourceUid = "prometheus";
                expr = "thorn_topology_conn_log_available{job=\"topology\"}";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "2m";
                noDataState = "OK";
                category = "pipeline";
                summary = "The topology reducer cannot read Zeek conn.log; its graph may be empty even while the renderer and Prometheus scrape remain healthy.";
              })
              (rule {
                # Audit-stack services have a dedicated inactive
                # detector below. Keep them out of this established
                # paging rule during the recording-only stage.
                uid = "siem-unit-failed";
                title = "systemd unit failed";
                datasourceUid = "prometheus";
                expr = ''
                  node_systemd_unit_state{
                    state="failed",
                    name!~"(rpc-auditor|ipc-auditor|session-auditor)\\.service"
                  } == 1
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "10m";
                summary = "A systemd unit has been in the failed state for 10 minutes.";
              })
              (rule {
                # Keep the warning and critical bands mutually
                # exclusive so a nearly-full disk produces one
                # notification, not two differently-coloured copies.
                uid = "fleet-root-disk-warning";
                title = "Root filesystem low on space";
                datasourceUid = "prometheus";
                expr = ''
                  (100 * (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) > 85)
                  unless
                  (100 * (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) > 95)
                '';
                evaluator = {
                  type = "gt";
                  params = [ 85 ];
                };
                for = "15m";
                summary = "A host has less than 15% free space on its root filesystem.";
              })
              (rule {
                uid = "fleet-root-disk-critical";
                title = "Root filesystem critically full";
                datasourceUid = "prometheus";
                expr = ''
                  100 * (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})
                '';
                evaluator = {
                  type = "gt";
                  params = [ 95 ];
                };
                for = "5m";
                severity = "critical";
                summary = "A host has less than 5% free space on its root filesystem; writes may fail imminently.";
              })
              (rule {
                uid = "fleet-root-inodes-low";
                title = "Root filesystem low on inodes";
                datasourceUid = "prometheus";
                expr = ''
                  100 * node_filesystem_files_free{mountpoint="/"} / node_filesystem_files{mountpoint="/"}
                '';
                evaluator = {
                  type = "lt";
                  params = [ 10 ];
                };
                for = "15m";
                summary = "A host has fewer than 10% of its root filesystem inodes free.";
              })
              (rule {
                uid = "fleet-root-readonly";
                title = "Root filesystem became read-only";
                datasourceUid = "prometheus";
                expr = ''node_filesystem_readonly{mountpoint="/"}'';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "2m";
                severity = "critical";
                summary = "A host's root filesystem is mounted read-only, usually following a storage or filesystem failure.";
              })
              (rule {
                uid = "fleet-memory-stall";
                title = "Sustained memory pressure";
                datasourceUid = "prometheus";
                expr = "100 * rate(node_pressure_memory_stalled_seconds_total[10m])";
                evaluator = {
                  type = "gt";
                  params = [ 10 ];
                };
                for = "15m";
                summary = "Processes have been fully stalled by memory pressure for over 10% of wall time.";
              })
              (rule {
                uid = "mac-ksm-disabled";
                title = "Proxmox KSM is not running";
                datasourceUid = "prometheus";
                expr = ''
                  (node_ksmd_run{instance="proxmox.guildedthorn.arpa:9100"} != bool 1)
                  or absent(node_ksmd_run{instance="proxmox.guildedthorn.arpa:9100"})
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "10m";
                noDataState = "OK";
                summary = "mac's adaptive KSM service or node_exporter ksmd collector is not reporting run=1; identical Proxmox guest pages are no longer being deduplicated.";
              })
              (rule {
                uid = "fleet-oom-kill";
                title = "Kernel OOM kill";
                datasourceUid = "prometheus";
                expr = "increase(node_vmstat_oom_kill[15m])";
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                severity = "critical";
                summary = "The kernel killed at least one process because the host ran out of memory.";
              })
              (rule {
                uid = "fleet-clock-unsynced";
                title = "System clock is not synchronized";
                datasourceUid = "prometheus";
                expr = "node_timex_sync_status";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "15m";
                summary = "A host's clock is unsynchronized; log correlation and certificate validation may become unreliable.";
              })
              (rule {
                uid = "soc-prometheus-backup-stale";
                title = "Prometheus backup is stale";
                datasourceUid = "prometheus";
                expr = ''time() - thorn_backup_last_success_seconds{dataset="soc"}'';
                evaluator = {
                  type = "gt";
                  params = [ 129600 ];
                };
                for = "15m";
                noDataState = "Alerting";
                summary = "The Prometheus and Grafana restic snapshot has not completed successfully in more than 36 hours.";
              })
              (rule {
                uid = "fleet-service-probe-down";
                title = "Critical service endpoint unreachable";
                datasourceUid = "prometheus";
                expr = "probe_success";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "3m";
                noDataState = "Alerting";
                severity = "critical";
                summary = "A blackbox-monitored public or infrastructure endpoint is unreachable or returning an unexpected status.";
              })
              (rule {
                uid = "fleet-service-probe-slow";
                title = "Service endpoint is persistently slow";
                datasourceUid = "prometheus";
                expr = "probe_duration_seconds";
                evaluator = {
                  type = "gt";
                  params = [ 5 ];
                };
                for = "10m";
                summary = "A monitored endpoint has taken more than five seconds to answer for ten minutes.";
              })
              (rule {
                uid = "deck-voice-e2e-failed";
                title = "Deck Voice acoustic pipeline failed";
                datasourceUid = "prometheus";
                expr = ''
                  (thorn_deck_voice_e2e_success == bool 0)
                  or (time() - thorn_deck_voice_e2e_last_success_seconds > bool 129600)
                  or absent(thorn_deck_voice_e2e_success)
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "10m";
                noDataState = "Alerting";
                severity = "critical";
                category = "voice";
                summary = "The real Deck Voice microphone, wake word, STT, conversation, TTS, and HDMI transaction failed or has not succeeded within 36 hours.";
              })
              (rule {
                uid = "fleet-tls-expiry-warning";
                title = "TLS certificate expires within 21 days";
                datasourceUid = "prometheus";
                expr = ''
                  (probe_ssl_earliest_cert_expiry{instance!~"${internalAcmeProbeRegex}"} - time() < 1814400)
                  unless
                  (probe_ssl_earliest_cert_expiry{instance!~"${internalAcmeProbeRegex}"} - time() < 604800)
                '';
                evaluator = {
                  type = "lt";
                  params = [ 1814400 ];
                };
                for = "15m";
                summary = "A monitored HTTPS endpoint's certificate expires within 21 days.";
              })
              (rule {
                uid = "fleet-tls-expiry-critical";
                title = "TLS certificate expires within 7 days";
                datasourceUid = "prometheus";
                expr = ''probe_ssl_earliest_cert_expiry{instance!~"${internalAcmeProbeRegex}"} - time()'';
                evaluator = {
                  type = "lt";
                  params = [ 604800 ];
                };
                for = "5m";
                severity = "critical";
                summary = "A monitored HTTPS endpoint's certificate expires within seven days or has already expired.";
              })
              (rule {
                uid = "fleet-internal-acme-expiry-critical";
                title = "Internal ACME certificate expires within 4 hours";
                datasourceUid = "prometheus";
                expr = ''probe_ssl_earliest_cert_expiry{instance=~"${internalAcmeProbeRegex}"} - time()'';
                evaluator = {
                  type = "lt";
                  params = [ 14400 ];
                };
                for = "10m";
                noDataState = "Alerting";
                severity = "critical";
                summary = "A 24-hour Anvil certificate has less than four hours remaining; automatic renewal is not keeping pace.";
              })
              (rule {
                uid = "soc-prometheus-config-reload";
                title = "Prometheus configuration reload failed";
                datasourceUid = "prometheus";
                expr = "prometheus_config_last_reload_successful";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "5m";
                noDataState = "Alerting";
                severity = "critical";
                category = "pipeline";
                summary = "Prometheus rejected its latest configuration and may be running stale scrape settings.";
              })
              (rule {
                uid = "soc-loki-wal-disk-full";
                title = "Loki WAL hit a full disk";
                datasourceUid = "prometheus";
                expr = "increase(loki_ingester_wal_disk_full_failures_total[10m])";
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                severity = "critical";
                category = "pipeline";
                summary = "Loki could not write its WAL because the local filesystem was full; log loss is possible.";
              })
              (rule {
                uid = "siem-ssh-bruteforce";
                title = "SSH brute force";
                datasourceUid = "loki";
                expr = ''
                  topk(20, sum by (host, src_ip) (count_over_time(
                    {job="systemd-journal", unit="sshd.service"}
                      |~ "Failed password|Invalid user"
                      | regexp `from (?P<src_ip>(?:[0-9]{1,3}\.){3}[0-9]{1,3})`
                      | src_ip != "" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 10 ];
                };
                for = "0s";
                severity = "critical";
                category = "security";
                summary = "More than 10 failed SSH logins on one host in 10 minutes.";
              })
              # Audit-stack observation phase. These five detection
              # families plus service health evaluate every minute
              # and preserve Grafana state/history, but the helper's
              # recordOnly label sends them through the permanently
              # muted policy route above. Remove recordOnly from an
              # individual rule only after its dashboard evidence has
              # been reviewed and its paging threshold is intentional.
              (rule {
                uid = "audit-container-exec";
                title = "Audit: container exec observed";
                datasourceUid = "loki";
                expr = ''
                  topk(50, sum by (host, container, image) (count_over_time(
                    {job="systemd-journal", unit="session-auditor.service"}
                      | json
                      | event = "container_exec" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                recordOnly = true;
                category = "security";
                summary = "A docker exec_create event was attributed to a container; review the container, image, and command in the Audit Stack dashboard.";
              })
              (rule {
                uid = "audit-tunnel-listener-new";
                title = "Audit: new SSH tunnel listener";
                datasourceUid = "loki";
                expr = ''
                  topk(50, sum by (host, listener) (count_over_time(
                    {job="systemd-journal", unit="session-auditor.service"}
                      | json
                      | event = "tunnel_listener_new" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                recordOnly = true;
                category = "security";
                summary = "An ssh/sshd-owned listener appeared on a nonstandard local port; confirm the port forward was intentional.";
              })
              (rule {
                uid = "audit-sensor-error";
                title = "Audit: sensor error event";
                datasourceUid = "loki";
                expr = ''
                  topk(50, sum by (host, unit, event, watcher) (count_over_time(
                    {job="systemd-journal", unit=~"(rpc|ipc|session)-auditor.service"}
                      | json
                      | event =~ "sensor_exit|cycle_failed|state_save_failed|watcher_failed|watcher_degraded|rate_overflow|cycle_overflow" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                recordOnly = true;
                category = "pipeline";
                summary = "An audit-stack component reported a sensor, watcher, persistence, or overflow failure.";
              })
              (rule {
                uid = "audit-sensor-inactive";
                title = "Audit: sensor service inactive";
                datasourceUid = "prometheus";
                expr = ''
                  1 - node_systemd_unit_state{name=~"(rpc-auditor|ipc-auditor|session-auditor)\\.service",state="active"}
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "5m";
                recordOnly = true;
                category = "pipeline";
                summary = "One of the three audit-stack systemd services has not remained active for five minutes.";
              })
              (rule {
                uid = "audit-ssh-auth-anomaly";
                title = "Audit: unusual SSH authentication";
                datasourceUid = "loki";
                expr = ''
                  topk(50, sum by (host, user, rhost, method) (count_over_time(
                    {job="systemd-journal", unit="session-auditor.service"}
                      | json
                      | service = "ssh"
                      | event = "auth_failure" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                recordOnly = true;
                category = "security";
                summary = "At least one SSH authentication failed; use the attributed user and remote host to decide whether it is routine or suspicious.";
              })
              (rule {
                uid = "audit-rpc-listener-new";
                title = "Audit: new RPC listener";
                datasourceUid = "loki";
                expr = ''
                  topk(50, sum by (host, endpoint) (count_over_time(
                    {job="systemd-journal", unit="rpc-auditor.service"}
                      | json
                      | event = "rpc_listener_new" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                recordOnly = true;
                category = "security";
                summary = "A loopback TCP or Unix-domain RPC listener appeared outside the persisted listener baseline.";
              })
              (rule {
                uid = "siem-suricata-alert";
                title = "Suricata IDS alert";
                datasourceUid = "loki";
                expr = ''
                  topk(20, sum by (host, src_ip, dest_ip) (count_over_time(
                    {job="suricata"}
                      | json
                      | event_type = "alert"
                      | src_ip != "" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                severity = "critical";
                category = "security";
                summary = "Suricata raised at least one IDS alert.";
              })
              (rule {
                # stats.log is emitted every five minutes even when
                # the protected network is quiet. Its absence tests
                # Zeek -> file -> Alloy -> Loki, rather than merely
                # whether the systemd process claims to be active.
                uid = "siem-zeek-silent";
                title = "Zeek network sensor is silent";
                datasourceUid = "loki";
                expr = "sum(count_over_time({job=\"zeek\", host=\"mac\", zeek_log=\"stats\"} [20m]))";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "15m";
                window = 1200;
                noDataState = "Alerting";
                severity = "critical";
                category = "pipeline";
                summary = "No Zeek stats heartbeat has reached Loki in 20 minutes — OPT1 network visibility is unavailable.";
              })
              (rule {
                uid = "siem-zeek-capture-loss";
                title = "Zeek estimates packet capture loss";
                datasourceUid = "loki";
                expr = ''
                  max_over_time({job="zeek", host="mac", zeek_log="capture_loss"}
                    | json | unwrap percent_lost | __error__="" [20m])
                '';
                evaluator = {
                  type = "gt";
                  params = [ 1 ];
                };
                for = "0s";
                window = 1200;
                category = "network";
                summary = "Zeek estimates that more than 1% of TCP data was missed; investigations may have incomplete network evidence.";
              })
              (rule {
                # stats.log reports the number dropped during each
                # five-minute sample, rather than a lifetime total.
                uid = "siem-zeek-kernel-drops";
                title = "Zeek capture socket dropped packets";
                datasourceUid = "loki";
                expr = ''
                  sum_over_time({job="zeek", host="mac", zeek_log="stats"}
                    | json | unwrap pkts_dropped | __error__="" [15m])
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                window = 900;
                category = "network";
                summary = "The kernel dropped packets before Zeek could inspect them; sensor CPU or capture buffering may need tuning.";
              })
              (rule {
                # Page only when the guessed service is inside the
                # protected OPT1 network. A local client mistyping a
                # password against an Internet host is not a SOC
                # incident for this environment.
                uid = "siem-zeek-ssh-password-guessing";
                title = "Zeek detected SSH password guessing";
                datasourceUid = "loki";
                expr = ''
                  topk(20, sum by (src, dst) (count_over_time(
                    {job="zeek", host="mac", zeek_log="notice"}
                      | json
                      | note = "SSH::Password_Guessing"
                      | src != ""
                      | dst =~ `172\.16\.25\..*` [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                severity = "critical";
                category = "security";
                summary = "Zeek observed at least 30 failed SSH authentications against an OPT1 host from one source within 30 minutes.";
              })
              (rule {
                uid = "siem-zeek-heartbleed";
                title = "Zeek detected TLS Heartbleed activity";
                datasourceUid = "loki";
                expr = ''
                  topk(20, sum by (src, dst) (count_over_time(
                    {job="zeek", host="mac", zeek_log="notice"}
                      | json
                      | note =~ "Heartbleed::SSL_Heartbeat_(Attack(_Success)?|Odd_Length|Many_Requests)"
                      | src != "" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                severity = "critical";
                category = "security";
                summary = "Zeek observed a suspicious TLS heartbeat request, scan, or probable Heartbleed exploit attempt.";
              })
              (rule {
                # Passive TLS certificate inspection is possible
                # only when the handshake exposes the certificate
                # (TLS 1.3 encrypts it). Blackbox probes remain the
                # direct check for known HTTPS endpoints.
                uid = "siem-zeek-local-certificate";
                title = "Zeek found a local TLS certificate problem";
                datasourceUid = "loki";
                expr = ''
                  sum(count_over_time({job="zeek", host="mac", zeek_log="notice"}
                    | json
                    | note =~ "SSL::(Invalid_Server_Cert|Certificate_Expired|Certificate_Expires_Soon|Certificate_Not_Valid_Yet)"
                    | dst =~ `172\.16\.25\..*` [1h]))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                window = 3600;
                category = "tls";
                summary = "Zeek observed an invalid, expired, not-yet-valid, or soon-expiring certificate from an OPT1 TLS service.";
              })
              (rule {
                # pfSense's perimeter Suricata arrives as raw syslog
                # (job=syslog), not EVE JSON, so match the priority
                # tag in the text. Only 1-2 (high/critical) alert,
                # to keep low-severity decoder noise off Discord.
                uid = "siem-pfsense-suricata";
                title = "pfSense Suricata high-severity alert";
                datasourceUid = "loki";
                expr = ''
                  topk(20, sum by (geoip_src_ip) (count_over_time(
                    {job="syslog", pfsense_log="suricata"}
                      |~ "Priority: [12]"
                      | geoip_src_ip != "" [10m]
                  )))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                severity = "critical";
                category = "security";
                summary = "pfSense's perimeter Suricata raised a high-severity (priority 1-2) alert.";
              })
              (rule {
                # Unlike DNS alone, the combined pfSense stream has
                # near-constant WAN filter activity. Its absence is
                # therefore a useful end-to-end receiver check.
                uid = "siem-pfsense-syslog-silent";
                title = "pfSense syslog feed is silent";
                datasourceUid = "loki";
                expr = "sum(count_over_time({job=\"syslog\", host=\"pfsense\"} [20m]))";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "15m";
                window = 1200;
                noDataState = "Alerting";
                severity = "critical";
                category = "pipeline";
                summary = "No pfSense DNS, firewall, or IDS syslog has reached Loki in 20 minutes.";
              })
              (rule {
                uid = "siem-pineapple-wireless-alert";
                title = "Pineapple detected a wireless security anomaly";
                datasourceUid = "loki";
                expr = ''
                  sum(count_over_time(
                    {job="syslog", host="pineapple"}
                      |= "wifi-watch"
                      |~ "deauth|untrusted BSSID" [5m]
                  ))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                severity = "critical";
                category = "security";
                summary = "The passive Pineapple sensor observed a deauthentication flood or rogue ThornCloud BSSID.";
              })
              (rule {
                uid = "siem-pineapple-heartbeat-silent";
                title = "Pineapple wireless sensor heartbeat is missing";
                datasourceUid = "loki";
                expr = ''
                  sum(count_over_time(
                    {job="syslog", host="pineapple"}
                      |= "wifi-watch"
                      |= "heartbeat" [15m]
                  ))
                '';
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "10m";
                window = 900;
                noDataState = "Alerting";
                severity = "critical";
                category = "pipeline";
                summary = "No Pineapple wifi-watch heartbeat has reached Loki in 15 minutes.";
              })
              (rule {
                # Group on structured metadata at query time rather
                # than indexing client addresses as stream labels.
                uid = "siem-pfsense-nxdomain-burst";
                title = "Client generated an NXDOMAIN burst";
                datasourceUid = "loki";
                expr = ''
                  sum by (dns_client_ip) (count_over_time(
                    {job="syslog", pfsense_log="dns", dns_event="reply", dns_rcode="NXDOMAIN"}
                      | dns_client_ip != ""
                      | keep dns_client_ip [10m]
                  ))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 50 ];
                };
                for = "0s";
                category = "security";
                summary = "One resolver client received more than 50 NXDOMAIN replies in 10 minutes; investigate mistyped automation, scanning, or DGA-like behavior.";
              })
              (rule {
                uid = "siem-pfsense-dns-servfail";
                title = "pfSense DNS SERVFAIL spike";
                datasourceUid = "loki";
                expr = "sum(count_over_time({job=\"syslog\", pfsense_log=\"dns\", dns_event=\"reply\", dns_rcode=\"SERVFAIL\"} [10m]))";
                evaluator = {
                  type = "gt";
                  params = [ 10 ];
                };
                for = "0s";
                category = "dns";
                summary = "Unbound returned more than 10 SERVFAIL responses in 10 minutes; upstream DNS, DNSSEC, or local resolver health may be degraded.";
              })
              (rule {
                # `in` on an internal interface means a client sent
                # the packet into pfSense. Restrict to IPv4 to avoid
                # routine link-local IPv6 multicast block noise.
                uid = "siem-pfsense-internal-block-burst";
                title = "Internal client repeatedly blocked by pfSense";
                datasourceUid = "loki";
                expr = ''
                  sum by (firewall_source_ip) (count_over_time(
                    {job="syslog", pfsense_log="firewall", firewall_interface=~"igb0|igb1", firewall_action="block", firewall_direction="in", firewall_ip_version="4"}
                      | firewall_source_ip != ""
                      | keep firewall_source_ip [10m]
                  ))
                '';
                evaluator = {
                  type = "gt";
                  params = [ 25 ];
                };
                for = "0s";
                category = "network";
                summary = "One LAN or OPT1 client hit pfSense block rules more than 25 times in 10 minutes.";
              })
              (rule {
                uid = "siem-crowdsec-alert";
                title = "CrowdSec scenario triggered";
                datasourceUid = "loki";
                expr = "sum by (host) (count_over_time({unit=\"crowdsec.service\"} |~ \"performed\" [10m]))";
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                category = "security";
                summary = "CrowdSec detected an attack scenario (detect-only, nothing was blocked).";
              })
              (rule {
                # A failed deploy leaves the host silently running
                # its previous generation — it stays up, keeps
                # shipping logs, and looks entirely healthy on every
                # other panel. Nothing else in this rule set would
                # notice.
                uid = "siem-comin-deploy-failed";
                title = "comin deploy failed";
                datasourceUid = "prometheus";
                expr = "comin_last_deployment_failed";
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "5m";
                category = "deployment";
                summary = "A host's last comin deployment failed — it is still running its previous configuration.";
              })
              (rule {
                # Build and eval failures are summed rather than
                # given a rule each: both mean "the pushed config
                # did not become a system", and the journal says
                # which. They carry identical label sets, so the
                # addition matches cleanly.
                uid = "siem-comin-build-failed";
                title = "comin build or eval failed";
                datasourceUid = "prometheus";
                expr = "comin_last_build_failed + comin_last_eval_failed";
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "5m";
                category = "deployment";
                summary = "A host failed to build or evaluate its configuration — the pushed commit never became a system.";
              })
              (rule {
                uid = "siem-comin-fetch-failed";
                title = "comin cannot fetch on an always-on host";
                datasourceUid = "prometheus";
                expr = ''comin_last_fetch_failed{instance=~"(${cominFetchInstanceRegex})"}'';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "15m";
                category = "deployment";
                summary = "An always-on host has been unable to fetch its deployment branch for 15 minutes.";
              })
              (rule {
                uid = "siem-comin-reboot-pending";
                title = "Deployed generation needs a reboot";
                datasourceUid = "prometheus";
                expr = "comin_need_to_reboot";
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "30m";
                category = "deployment";
                summary = "A host deployed successfully but still needs a reboot for its kernel or initrd change to take effect.";
              })
              (rule {
                uid = "siem-loki-down";
                title = "Log pipeline down (Loki unreachable)";
                datasourceUid = "prometheus";
                expr = "up{job=\"loki\"}";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "5m";
                noDataState = "Alerting";
                severity = "critical";
                category = "pipeline";
                summary = "Prometheus can't scrape Loki on soc — the SIEM may be blind to new logs.";
              })
            ]
            ++ lib.optionals securityWorkflowReady [
              (rule {
                uid = "siem-security-relay-down";
                title = "Security incident relay is down";
                datasourceUid = "prometheus";
                expr = ''up{job="security-relay"}'';
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "5m";
                noDataState = "Alerting";
                severity = "critical";
                category = "pipeline";
                summary = "SOC cannot deliver critical security detections to OpenCTI and TheHive; Discord remains active.";
              })
              (rule {
                uid = "siem-security-relay-delivery-failed";
                title = "Security incident delivery failed";
                datasourceUid = "prometheus";
                expr = "increase(thorn_security_relay_alerts_failed_total[15m])";
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                severity = "critical";
                category = "pipeline";
                summary = "The security relay could not create at least one TheHive alert; Grafana will retry and Discord remains active.";
              })
            ]
            # OpenCanary is deliberately excluded from blackbox
            # probes: touching any decoy port is itself an event.
            # Alert directly from its structured JSON instead.
            ++ lib.optionals lureTelemetryReady [
              (rule {
                uid = "siem-opencanary-interaction";
                title = "OpenCanary decoy service touched";
                datasourceUid = "loki";
                expr = ''sum by (src_host, dst_port) (count_over_time({job="systemd-journal", host="lure"} | json | src_host != "" [5m]))'';
                evaluator = {
                  type = "gt";
                  params = [ 0 ];
                };
                for = "0s";
                window = 300;
                severity = "critical";
                category = "security";
                summary = "A host interacted with an instrumented service on Lure; investigate the source and destination port immediately.";
              })
            ]
            # Detection canaries. Each canary host runs a uniquely
            # named probe every 10 minutes; this asserts the
            # resulting execve record actually arrives in Loki.
            #
            # This is the only rule here that tests the detection
            # pipeline rather than the systems being watched. Every
            # other rule assumes auditd -> journal -> Alloy -> Loki
            # -> query works and reports on what it finds; this one
            # fails loudly when that assumption stops holding. It
            # exists because the assumption did stop holding once
            # already — a wrong LogQL filter left every audit panel
            # silently empty for weeks, indistinguishable from a
            # quiet fleet.
            #
            # 30m window against a 10m timer tolerates two
            # consecutive misses, so a slow scrape or brief Loki
            # blip doesn't page. noDataState = Alerting for the
            # same reason as the log-silence rules: total absence
            # produces no series to threshold against, and absence
            # is exactly the signal.
            ++ map (
              host:
              rule {
                uid = "siem-canary-silent-${host}";
                title = "Detection canary silent on ${host}";
                datasourceUid = "loki";
                # unit exclusion: Loki logs every query it executes
                # (msg="executing query"), and this rule's own query
                # text contains the probe string — without it, the
                # rule for the host Loki runs on is pacified by the
                # echo of its own evaluation and can never fire.
                expr = "sum(count_over_time({job=\"systemd-journal\", host=\"${host}\", unit!~\"loki.service|grafana.service\"} |= \"siem-canary-probe\" [30m]))";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "5m";
                window = 1800;
                noDataState = "Alerting";
                severity = "critical";
                category = "pipeline";
                summary = "The detection canary on ${host} has not reached Loki in 30 minutes — the audit/log pipeline is broken and this host's security telemetry cannot be trusted.";
              }
            ) canaryHosts
            # Per-host log-silence detection, one rule per always-on
            # host. This replaces a single fleet-wide
            # sum(count_over_time(...)) rule, which could only ever
            # catch TOTAL ingest failure: as long as one chatty host
            # kept shipping, the sum stayed healthy and a single
            # host going dark was invisible. Silencing the log
            # shipper is step one of a competent intrusion, so
            # per-host is the resolution that actually matters.
            #
            # noDataState = Alerting is load-bearing, not
            # decoration: a host that has gone completely silent
            # produces NO series for its matcher (LogQL sum() over
            # an empty vector returns empty, not zero), so the
            # threshold never evaluates and only the NoData path
            # fires. An "OK on no data" rule here would be exactly
            # backwards — silence is the signal.
            #
            # Scoped to `fleet` for the same reason Prometheus
            # scrapes only those hosts: the laptops and lab VMs are
            # legitimately offline much of the time and would alert
            # constantly.
            ++ map (
              host:
              rule {
                uid = "siem-log-silent-${host}";
                title = "Log silence from ${host}";
                datasourceUid = "loki";
                expr = "sum(count_over_time({job=\"systemd-journal\", host=\"${host}\"} [15m]))";
                evaluator = {
                  type = "lt";
                  params = [ 1 ];
                };
                for = "5m";
                window = 900;
                noDataState = "Alerting";
                severity = "critical";
                category = "pipeline";
                summary = "No journal lines have reached Loki from ${host} in 15 minutes — either the host is down or its log shipping has stopped.";
              }
            ) fleetJournalHosts;
        }
      ];
    };
  };
}
