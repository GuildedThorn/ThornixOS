{ config, inputs, ... }:
{
  flake.nixosConfigurations.soc = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

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
          # fleet-wide by services-observability). A powered-off lab VM just
          # shows as down.
          fleet = [
            # "firewall" is in the flake but not deployed — pfSense is the
            # router for now; add it back here when it's wired up.
            "mac"
            "mitm"
            "nixos"
            "proxmox-guest"
            "scout"
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

          # Syslog → Loki ingest for non-NixOS devices (pfSense today; any
          # appliance that can't run Alloy). soc's Alloy — already shipping
          # soc's own journal via services-observability — gains a syslog
          # listener that forwards into Loki through the same loki.write.soc
          # receiver. Port 5514 (unprivileged) so Alloy's DynamicUser can
          # bind it without extra capabilities; point the sender at
          # 172.16.25.51:5514. Host/app labels come from the syslog header,
          # so many devices can share this one listener. When the firewall
          # becomes a NixOS host it ships via journal instead and this stays
          # for everything else.
          networking.firewall.allowedUDPPorts = [ 5514 ];
          environment.etc."alloy/syslog.alloy".text = ''
            loki.source.syslog "network" {
              listener {
                address  = "0.0.0.0:5514"
                protocol = "udp"
                labels   = { job = "syslog" }
                # pfSense/FreeBSD syslogd emits old BSD-style RFC3164, not
                # the RFC5424 Alloy defaults to (which expects a version
                # field — "error parsing syslog stream" without this).
                syslog_format = "rfc3164"
              }
              relabel_rules = loki.relabel.syslog.rules
              forward_to    = [loki.write.soc.receiver]
            }

            loki.relabel "syslog" {
              forward_to = []
              rule {
                source_labels = ["__syslog_message_hostname"]
                target_label  = "host"
              }
              rule {
                source_labels = ["__syslog_message_app_name"]
                target_label  = "app"
              }
              rule {
                source_labels = ["__syslog_message_severity"]
                target_label  = "severity"
              }
            }
          '';

          services.grafana = {
            enable = true;
            settings = {
              server = {
                http_addr = "0.0.0.0";
                http_port = 3000;
                domain = "soc.guildedthorn.arpa";
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

              # SOC Phase 3: correlation/alerting rules, visible in the
              # Grafana alerting UI. No contact points yet — deliberately
              # dashboard-only until a notification channel is picked.
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
                            noDataState ? "OK",
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
                            data = [
                              {
                                refId = "A";
                                inherit datasourceUid;
                                relativeTimeRange = {
                                  from = 600;
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
                          summary = "Suricata raised at least one IDS alert.";
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
                          summary = "Prometheus can't scrape Loki on soc — the SIEM may be blind to new logs.";
                        })
                        (rule {
                          uid = "siem-log-ingest-stalled";
                          title = "Log ingest stalled (no new journal lines)";
                          datasourceUid = "loki";
                          expr = "sum(count_over_time({job=\"systemd-journal\"} [10m]))";
                          evaluator = {
                            type = "lt";
                            params = [ 1 ];
                          };
                          for = "10m";
                          noDataState = "Alerting";
                          summary = "No journal lines reached Loki from any host in 10 minutes — shipping is broken.";
                        })
                      ];
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
