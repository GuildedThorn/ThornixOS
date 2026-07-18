{ config, inputs, ... }:
{
  flake.nixosConfigurations.soc = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      # The SIEM host is worth defending too — an attacker who reaches soc
      # can rewrite the record of how they got in.
      config.nixos.modules.services-crowdsec
      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/soc/hardware-configuration.nix"
      "${inputs.self}/hosts/soc/disko.nix"
      "${inputs.self}/hosts/soc/networking.nix"
      "${inputs.self}/hosts/soc/secrets.nix"

      (
        { config, lib, ... }:
        let
          # SeaweedFS S3 gateway on the NAS. Loki keeps only its WAL and
          # caches on the VM disk; all chunk/index storage lives in the
          # `loki` bucket, so this VM is rebuildable without data loss.
          seaweedfsS3 = "truenas.guildedthorn.arpa:30304";

          # Hosts Prometheus scrapes for node metrics (port 9100, opened
          # fleet-wide by services-observability). Only the always-on hosts:
          # the laptops (mac, scout) and lab VMs (mitm, proxmox-guest) are
          # intermittent, so scraping them just yields a permanent "down"
          # and noisy host-down alerts. They still ship LOGS (Alloy pushes
          # whenever they're up); add one back here if it becomes always-on.
          # "firewall" is in the flake but not deployed — pfSense fills that
          # role for now.
          fleet = [
            "nixos"
            "soc"
            "websites"
          ];
        in
        {
          # Trust the LAN CA so Loki's S3 client can verify the SeaweedFS
          # gateway's certificate.
          security.pki.certificates = [
            (builtins.readFile "${inputs.self}/certs/ThornCloud_CA.crt")
          ];

          boot = {
            growPartition = true;
            # BIOS boot via GRUB on the whole disk. disko already registers
            # /dev/sda as a GRUB device; force a single entry so the two
            # definitions don't merge into a duplicate (mirroredBoots assert).
            loader.grub = {
              enable = true;
              devices = lib.mkForce [ "/dev/sda" ];
              efiSupport = false;
            };
            # Keep the NIC named eth0, matching the static config in
            # hosts/soc/networking.nix (same as websites).
            kernelParams = [ "net.ifnames=0" ];
          };
          services.qemuGuest.enable = true;

          services.openssh.settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
          };
          # Workstation key — headless host, no other login path.
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+iFLtqnhkscz2qLK45nJVmGZIbQvIeIuW8tenAjX2p thorn@workstation"
          ];

          services.loki = {
            enable = true;
            # Lets the config reference the S3 credentials as ${ENV_VAR}
            # from the sops-templated EnvironmentFile below.
            extraFlags = [ "--config.expand-env=true" ];
            configuration = {
              auth_enabled = false;

              server.http_listen_port = 3100;

              common = {
                path_prefix = "/var/lib/loki";
                replication_factor = 1;
                ring = {
                  instance_addr = "127.0.0.1";
                  kvstore.store = "inmemory";
                };
                storage.s3 = {
                  endpoint = seaweedfsS3;
                  bucketnames = "loki";
                  region = "us-east-1";
                  access_key_id = "\${LOKI_S3_ACCESS_KEY_ID}";
                  secret_access_key = "\${LOKI_S3_SECRET_ACCESS_KEY}";
                  # HTTPS with a ThornCloud_CA cert (trusted via
                  # security.pki below). SeaweedFS doesn't do virtual-hosted
                  # bucket addressing.
                  s3forcepathstyle = true;
                };
              };

              schema_config.configs = [
                {
                  from = "2026-01-01";
                  store = "tsdb";
                  object_store = "s3";
                  schema = "v13";
                  index = {
                    prefix = "index_";
                    period = "24h";
                  };
                }
              ];

              storage_config.tsdb_shipper = {
                active_index_directory = "/var/lib/loki/tsdb-index";
                cache_location = "/var/lib/loki/tsdb-cache";
              };

              compactor = {
                working_directory = "/var/lib/loki/compactor";
                retention_enabled = true;
                delete_request_store = "s3";
              };

              limits_config = {
                retention_period = "90d";
                reject_old_samples = true;
                reject_old_samples_max_age = "168h";
              };
            };
          };
          systemd.services.loki.serviceConfig.EnvironmentFile = config.sops.templates."loki-s3.env".path;

          # Metrics stay on the VM disk — small at this fleet size, and
          # object storage for Prometheus means Thanos/Mimir complexity
          # that isn't worth it yet.
          services.prometheus = {
            enable = true;
            retentionTime = "90d";
            # Accept pushed metrics from roaming hosts (scout via
            # services-observability-roaming) that can't be scraped.
            extraFlags = [ "--web.enable-remote-write-receiver" ];
            globalConfig.scrape_interval = "30s";
            scrapeConfigs = [
              {
                job_name = "node";
                static_configs = [
                  { targets = map (host: "${host}.guildedthorn.arpa:9100") fleet; }
                ];
              }
              # pfSense (node_exporter package). Kept in its own job with an
              # explicit instance label because it's not a flake host, and
              # addressed by IP — pfsense.guildedthorn.arpa's own override
              # oddly resolves to the other subnet (192.168.1.1).
              {
                job_name = "pfsense";
                static_configs = [
                  {
                    targets = [ "172.16.25.1:9100" ];
                    labels.instance = "pfsense.guildedthorn.arpa:9100";
                  }
                ];
              }
              # Loki's own metrics — lets us alert when the log pipeline
              # itself breaks (soc going blind is worse than any single
              # host going down, since it's the thing that would tell us).
              {
                job_name = "loki";
                static_configs = [ { targets = [ "127.0.0.1:3100" ]; } ];
              }
            ];
          };

          # Prometheus TSDB backup to the NAS. Loki's chunks already live in
          # object storage, so soc has always been "rebuildable without data
          # loss" for LOGS only — metrics sat on the VM disk with no copy
          # anywhere, and a rebuild silently took 90 days of history with it.
          #
          # Backing up the data directory directly rather than going through
          # Prometheus's snapshot API: the API route needs
          # --web.enable-admin-api, and 9090 is reachable from the whole LAN
          # (it has to be, for scout's remote-write). That admin surface
          # includes delete-series, so enabling it would hand every host on
          # the subnet a way to erase the metrics this backup exists to
          # protect. Not a good trade for a cleaner snapshot.
          #
          # The cost of that choice: TSDB blocks are immutable once written,
          # but the in-memory head is flushed through a live WAL, so a
          # restic run can capture a torn tail. Prometheus truncates a
          # partial WAL on replay, so a restore loses at most the last
          # (unflushed) couple of hours rather than failing to start.
          services.restic.backups.prometheus = {
            initialize = true;
            repository = "s3:https://${seaweedfsS3}/prometheus-backup";
            passwordFile = config.sops.secrets.restic_password.path;
            environmentFile = config.sops.templates."restic-s3.env".path;
            paths = [ "/var/lib/${config.services.prometheus.stateDir}" ];
            timerConfig = {
              OnCalendar = "daily";
              # Spread load off the top of the hour; Persistent catches up a
              # run the VM slept through.
              RandomizedDelaySec = "1h";
              Persistent = true;
            };
            pruneOpts = [
              "--keep-daily 7"
              "--keep-weekly 4"
              "--keep-monthly 3"
            ];
          };

          # Syslog → Loki ingest for non-NixOS devices (pfSense today; any
          # appliance that can't run Alloy). pfSense's FreeBSD syslogd emits
          # a non-standard RFC3164 with NO hostname field
          # (`<pri>TIMESTAMP tag: msg`), which Alloy's strict syslog parser
          # rejects outright. So rsyslog fronts it: it tolerantly accepts the
          # datagrams on 5514/udp, fills the missing hostname from the source
          # IP, and writes one file per source under /var/log/remote; Alloy
          # then tails those into Loki via the same loki.write.soc receiver.
          # Files are 0644 so Alloy's DynamicUser can read them. When the
          # firewall becomes a NixOS host it ships via journal instead and
          # this stays for other appliances.
          networking.firewall.allowedUDPPorts = [ 5514 ];
          services.rsyslogd = {
            enable = true;
            extraConfig = ''
              module(load="imudp")
              input(type="imudp" port="5514")
              template(name="remotefile" type="string"
                       string="/var/log/remote/%FROMHOST-IP%.log")
              if ($fromhost-ip != "127.0.0.1") then {
                action(type="omfile" dynaFile="remotefile"
                       fileCreateMode="0644" dirCreateMode="0755")
                stop
              }
            '';
          };
          environment.etc."alloy/syslog.alloy".text = ''
            // loki.source.file tails exact paths only, so discover the
            // per-source files under /var/log/remote via a glob first.
            local.file_match "remote_syslog" {
              path_targets = [{
                "__path__" = "/var/log/remote/*.log",
                job        = "syslog",
                host       = "pfsense",
              }]
            }

            loki.source.file "remote_syslog" {
              targets    = local.file_match.remote_syslog.targets
              forward_to = [loki.write.soc.receiver]
            }
          '';

          services.grafana = {
            enable = true;
            settings = {
              server = {
                # TLS via a ThornCloud_CA-signed cert (the fleet already
                # trusts that CA — see security.pki above), so no browser
                # warnings and admin creds/SIEM data don't cross the LAN in
                # cleartext (relevant with MITM lab boxes on the network).
                # Cert lives in the repo; the private key stays in sops.
                # NOTE: soc's deploy needs BOTH certs/soc.guildedthorn.arpa.crt
                # committed AND the grafana_tls_key secret present, or Grafana
                # won't start — add both before pushing this.
                protocol = "https";
                http_addr = "0.0.0.0";
                http_port = 3000;
                domain = "soc.guildedthorn.arpa";
                root_url = "https://soc.guildedthorn.arpa:3000";
                cert_file = "${inputs.self}/certs/soc.guildedthorn.arpa.crt";
                cert_key = config.sops.secrets.grafana_tls_key.path;
                enable_gzip = true;
              };
              security.admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
              security.secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
              analytics.reporting_enabled = false;
            };
            provision = {
              enable = true;
              # The datasources originally provisioned without explicit
              # uids; Grafana can't change a uid in place ("data source not
              # found" crash loop), so drop and re-create them each start.
              datasources.settings.deleteDatasources = [
                {
                  name = "Loki";
                  orgId = 1;
                }
                {
                  name = "Prometheus";
                  orgId = 1;
                }
              ];
              datasources.settings.datasources = [
                {
                  name = "Loki";
                  type = "loki";
                  uid = "loki";
                  url = "http://127.0.0.1:3100";
                }
                {
                  name = "Prometheus";
                  type = "prometheus";
                  uid = "prometheus";
                  url = "http://127.0.0.1:9090";
                  isDefault = true;
                }
              ];

              dashboards.settings.providers = [
                {
                  name = "thornix";
                  folder = "SIEM";
                  # UI tweaks are allowed but live only until the next
                  # deploy — the JSON in the repo is the source of truth.
                  allowUiUpdates = true;
                  options.path = "${inputs.self}/hosts/soc/dashboards";
                }
              ];

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
                ];
              };

              # Route everything to Discord, but split by the `severity`
              # label the rule helper sets. There's still only one webhook —
              # the split buys timing, not destination: critical alerts
              # (active hostility, or the SIEM going blind) page out fast and
              # keep re-notifying until dealt with, while warnings batch up
              # and stay quiet. Without this, a Suricata hit waits behind the
              # same 30s/4h treatment as a systemd unit that failed once.
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
                    ];
                    group_wait = "30s";
                    group_interval = "5m";
                    repeat_interval = "4h";
                    routes = [
                      {
                        receiver = "discord";
                        object_matchers = [
                          [
                            "severity"
                            "="
                            "critical"
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
                            noDataState ? "OK",
                            # Lookback the rule evaluates over, in seconds.
                            # Keep in sync with the range selector in `expr`
                            # for Loki rules — the expression's own `[10m]`
                            # is what actually bounds the count.
                            window ? 600,
                          }:
                          {
                            inherit
                              uid
                              title
                              for
                              noDataState
                              ;
                            condition = "C";
                            execErrState = "Error";
                            annotations.summary = summary;
                            labels.severity = severity;
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
                                  expression = "A";
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
                          uid = "siem-unit-failed";
                          title = "systemd unit failed";
                          datasourceUid = "prometheus";
                          expr = "node_systemd_unit_state{state=\"failed\"} == 1";
                          evaluator = {
                            type = "gt";
                            params = [ 0 ];
                          };
                          for = "10m";
                          summary = "A systemd unit has been in the failed state for 10 minutes.";
                        })
                        (rule {
                          uid = "siem-ssh-bruteforce";
                          title = "SSH brute force";
                          datasourceUid = "loki";
                          expr = "sum by (host) (count_over_time({job=\"systemd-journal\", unit=\"sshd.service\"} |~ \"Failed password|Invalid user\" [10m]))";
                          evaluator = {
                            type = "gt";
                            params = [ 10 ];
                          };
                          for = "0s";
                          severity = "critical";
                          summary = "More than 10 failed SSH logins on one host in 10 minutes.";
                        })
                        (rule {
                          uid = "siem-suricata-alert";
                          title = "Suricata IDS alert";
                          datasourceUid = "loki";
                          expr = "sum by (host) (count_over_time({job=\"suricata\"} | json | event_type = \"alert\" [10m]))";
                          evaluator = {
                            type = "gt";
                            params = [ 0 ];
                          };
                          for = "0s";
                          severity = "critical";
                          summary = "Suricata raised at least one IDS alert.";
                        })
                        (rule {
                          # pfSense's perimeter Suricata arrives as raw syslog
                          # (job=syslog), not EVE JSON, so match the priority
                          # tag in the text. Only 1-2 (high/critical) alert,
                          # to keep low-severity decoder noise off Discord.
                          uid = "siem-pfsense-suricata";
                          title = "pfSense Suricata high-severity alert";
                          datasourceUid = "loki";
                          expr = "sum(count_over_time({job=\"syslog\"} |~ \"Priority: [12]\" [10m]))";
                          evaluator = {
                            type = "gt";
                            params = [ 0 ];
                          };
                          for = "0s";
                          severity = "critical";
                          summary = "pfSense's perimeter Suricata raised a high-severity (priority 1-2) alert.";
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
                          summary = "CrowdSec detected an attack scenario (detect-only, nothing was blocked).";
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
                          summary = "Prometheus can't scrape Loki on soc — the SIEM may be blind to new logs.";
                        })
                      ]
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
                          summary = "No journal lines have reached Loki from ${host} in 15 minutes — either the host is down or its log shipping has stopped.";
                        }
                      ) fleet;
                  }
                ];
              };
            };
          };
        }
      )
    ];
  };
}
