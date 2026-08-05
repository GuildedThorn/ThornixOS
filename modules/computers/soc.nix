{ config, inputs, ... }:
{
  flake.nixosConfigurations.soc = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      # The SIEM host is worth defending too — an attacker who reaches soc
      # can rewrite the record of how they got in.
      config.nixos.modules.services-crowdsec
      config.nixos.modules.services-canary
      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/soc/hardware-configuration.nix"
      "${inputs.self}/hosts/soc/disko.nix"
      "${inputs.self}/hosts/soc/networking.nix"
      "${inputs.self}/hosts/soc/secrets.nix"

      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          # SeaweedFS S3 gateway on the NAS. Loki keeps only its WAL and
          # caches on the VM disk; all chunk/index storage lives in the
          # `loki` bucket, so this VM is rebuildable without data loss.
          seaweedfsS3 = "truenas.guildedthorn.arpa:30304";

          # Probe the services users and the monitoring stack actually depend
          # on, from the same network vantage point as soc. `http_alive`
          # deliberately accepts auth responses: a 401/403 from S3 proves the
          # TLS listener and application are alive, while a 5xx still fails.
          blackboxConfig = pkgs.writeText "blackbox-exporter.yml" ''
            modules:
              http_alive:
                prober: http
                timeout: 10s
                http:
                  preferred_ip_protocol: ip4
                  follow_redirects: true
                  valid_status_codes: [200, 204, 301, 302, 401, 403]
                  tls_config:
                    ca_file: ${config.security.pki.caBundle}
          '';

          telemetryServerCertificate = "${inputs.self}/certs/soc.guildedthorn.arpa.crt";
          telemetryServerKey = config.sops.secrets.grafana_tls_key.path;

          # Both public telemetry ports use the same server identity and
          # ThornCloud_CA client trust. The per-location CN checks below
          # reduce each certificate to its intended read or write role.
          telemetryVhost = port: {
            serverName = "soc.guildedthorn.arpa";
            # `onlySSL` also tells the NixOS nginx module to emit the
            # certificate directives when an explicit SSL listen is used.
            onlySSL = true;
            listen = [
              {
                addr = "0.0.0.0";
                inherit port;
                ssl = true;
              }
            ];
            sslCertificate = telemetryServerCertificate;
            sslCertificateKey = telemetryServerKey;
            extraConfig = ''
              ssl_client_certificate ${inputs.self}/certs/ThornCloud_CA.crt;
              ssl_verify_client on;
              ssl_verify_depth 1;

              client_max_body_size 32m;

              allow 172.16.25.0/24;
              allow 10.10.10.3;
              deny all;
            '';
          };

          writerOnly = ''
            if ($ssl_client_s_dn !~ "(^|,)CN=thornix-telemetry-writer(,|$)") {
              return 403;
            }
            if ($request_method != POST) {
              return 405;
            }
          '';

          readerOnly = ''
            if ($ssl_client_s_dn !~ "(^|,)CN=thornix-telemetry-reader(,|$)") {
              return 403;
            }
            if ($request_method !~ "^(GET|POST)$") {
              return 405;
            }
          '';

          # Hosts Prometheus scrapes for node metrics (port 9100, opened
          # fleet-wide by services-observability). Only the always-on hosts:
          # scout and the lab VMs (mitm, proxmox-guest) are intermittent, so
          # scraping them just yields permanent "down" noise. They still ship
          # logs whenever they are up.
          #
          # journalHost is the machine's kernel hostname and therefore its
          # Loki label. metricsHost is its LAN DNS identity; they differ for
          # mac now that it is the Proxmox host.
          # "firewall" is in the flake but not deployed — pfSense fills that
          # role for now.
          fleet = [
            {
              journalHost = "nixos";
              metricsHost = "nixos.guildedthorn.arpa";
            }
            {
              journalHost = "mac";
              metricsHost = "proxmox.guildedthorn.arpa";
            }
            {
              journalHost = "soc";
              metricsHost = "soc.guildedthorn.arpa";
            }
            {
              journalHost = "websites";
              metricsHost = "websites.guildedthorn.arpa";
            }
          ];
          fleetJournalHosts = map (host: host.journalHost) fleet;
          fleetMetricsTargets = port: map (host: "${host.metricsHost}:${port}") fleet;

          # Hosts running services-canary — i.e. those with
          # thorn.audit.execScope = "all", where a systemd-timer process is
          # actually visible to the execve rule. Desktops are deliberately
          # absent: under the "sessions" scope the canary would never be
          # recorded, and they generate continuous real user exec activity
          # anyway, which is its own liveness signal.
          canaryHosts = [
            "mac"
            "soc"
            "websites"
          ];
        in
        {
          # Headless: nobody logs in interactively, so the default
          # "sessions" exec scope would record nothing at all here. See
          # services-audit for the reasoning and the volume trade.
          thorn.audit.execScope = "all";

          # pfSense cannot run Alloy itself, so its high-priority IDS source
          # addresses are enriched here after rsyslog receives them.
          thorn.geoip.enable = true;

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
          # Workstation keys — headless host, no other login path.
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+iFLtqnhkscz2qLK45nJVmGZIbQvIeIuW8tenAjX2p thorn@workstation"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIESh83q74VIIDGsHLvu6a1ptpmkae739Nz8SshW58eWY thorn"
          ];

          services.loki = {
            enable = true;
            # Lets the config reference the S3 credentials as ${ENV_VAR}
            # from the sops-templated EnvironmentFile below.
            extraFlags = [ "--config.expand-env=true" ];
            configuration = {
              auth_enabled = false;

              # No network client can reach Loki directly. nginx owns the
              # familiar :3100 port and proxies only explicitly allowed API
              # paths after client-certificate authorization.
              server = {
                http_listen_address = "127.0.0.1";
                http_listen_port = 3101;
                grpc_listen_address = "127.0.0.1";
              };

              common = {
                # In single-binary mode the query frontend advertises this
                # address to the colocated querier. Keep it aligned with the
                # loopback-only gRPC listener above; otherwise queries are
                # sent to 172.16.25.51:9095 and fail with connection refused.
                instance_addr = "127.0.0.1";
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
                # GeoIP values are intentionally structured metadata instead
                # of indexed labels. Schema v13 above stores that metadata in
                # chunk format v4 without exploding stream cardinality.
                allow_structured_metadata = true;
                retention_period = "90d";
                reject_old_samples = true;
                reject_old_samples_max_age = "168h";
              };
            };
          };
          systemd.services.loki.serviceConfig.EnvironmentFile = config.sops.templates."loki-s3.env".path;

          # HTTP/TLS reachability and certificate telemetry for the public
          # site and the LAN services the SOC itself depends on. It listens
          # only on loopback; Prometheus is its sole caller.
          services.prometheus.exporters.blackbox = {
            enable = true;
            listenAddress = "127.0.0.1";
            configFile = blackboxConfig;
          };

          # Metrics stay on the VM disk — small at this fleet size, and
          # object storage for Prometheus means Thanos/Mimir complexity
          # that isn't worth it yet.
          services.prometheus = {
            enable = true;
            listenAddress = "127.0.0.1";
            port = 9091;
            retentionTime = "90d";
            # Accept pushed metrics from roaming hosts (scout via
            # services-observability-roaming) that can't be scraped.
            extraFlags = [ "--web.enable-remote-write-receiver" ];
            globalConfig.scrape_interval = "30s";
            scrapeConfigs = [
              {
                job_name = "node";
                static_configs = [
                  { targets = fleetMetricsTargets "9100"; }
                ];
                # mac's textfile collector also carries the fast-changing
                # live topology snapshot. Keep it out of the ordinary 30s
                # node job so there is only one copy of those series.
                metric_relabel_configs = [
                  {
                    source_labels = [ "__name__" ];
                    regex = "thorn_topology_.*";
                    action = "drop";
                  }
                ];
              }
              # Scrape only node_exporter's textfile collector at dashboard
              # speed. This reuses the existing SOC-only :9100 firewall path;
              # no topology HTTP service is exposed from the hypervisor.
              {
                job_name = "topology";
                scrape_interval = "10s";
                scrape_timeout = "5s";
                params."collect[]" = [ "textfile" ];
                static_configs = [
                  { targets = [ "proxmox.guildedthorn.arpa:9100" ]; }
                ];
                metric_relabel_configs = [
                  {
                    source_labels = [ "__name__" ];
                    regex = "thorn_topology_.*|node_textfile_(mtime_seconds|scrape_error)";
                    action = "keep";
                  }
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
                static_configs = [ { targets = [ "127.0.0.1:3101" ]; } ];
              }
              # Monitor the monitoring stack itself. Without these jobs a
              # memory leak, query storm, or failed config reload remains
              # invisible until the service falls over completely.
              {
                job_name = "prometheus";
                scrape_interval = "60s";
                static_configs = [ { targets = [ "127.0.0.1:9091" ]; } ];
              }
              {
                job_name = "grafana";
                # Grafana exposes several thousand internal series; minute
                # resolution is ample and halves their 90-day TSDB cost.
                scrape_interval = "60s";
                scheme = "https";
                tls_config.ca_file = config.security.pki.caBundle;
                static_configs = [ { targets = [ "soc.guildedthorn.arpa:3000" ]; } ];
              }
              # Multi-target exporter pattern: retain the URL as `instance`,
              # pass it to blackbox as `target`, and scrape the local probe.
              {
                job_name = "blackbox-http";
                scrape_interval = "60s";
                metrics_path = "/probe";
                params.module = [ "http_alive" ];
                static_configs = [
                  {
                    targets = [
                      "https://guildedthorn.com/"
                      "https://soc.guildedthorn.arpa:3000/api/health"
                      "http://127.0.0.1:3101/ready"
                      "http://127.0.0.1:9091/-/ready"
                      "https://proxmox.guildedthorn.arpa:8006/"
                      "https://truenas.guildedthorn.arpa/"
                      "https://truenas.guildedthorn.arpa:30304/"
                      "https://pfsense.guildedthorn.arpa/"
                    ];
                  }
                ];
                relabel_configs = [
                  {
                    source_labels = [ "__address__" ];
                    target_label = "__param_target";
                  }
                  {
                    source_labels = [ "__param_target" ];
                    target_label = "instance";
                  }
                  {
                    target_label = "__address__";
                    replacement = "127.0.0.1:9115";
                  }
                ];
              }
              # comin — the deploy layer. Everything else scraped here says
              # whether a host is alive; this says whether it's running the
              # config that was pushed. comin_deployment_info carries the
              # deployed commit id as a label, so a stale host is visible
              # rather than something you discover by SSH.
              #
              # Roaming hosts aren't listed: they push this same job over
              # remote-write via services-observability-roaming, using
              # matching job/instance labels so both paths land in one series
              # set.
              {
                job_name = "comin";
                # Deploys are minute-scale at best; scraping faster just adds
                # samples that can't differ.
                scrape_interval = "60s";
                static_configs = [
                  { targets = fleetMetricsTargets "4243"; }
                ];
              }
            ];
          };

          # Authenticated ingress for the two telemetry backends. Loki and
          # Prometheus remain unauthenticated internally because their only
          # listener is loopback; nginx is the network security boundary.
          # Deliberately enumerate APIs instead of proxying broad prefixes:
          # neither identity can reach delete, admin, status, or lifecycle
          # endpoints over the network.
          services.nginx = {
            enable = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;
            virtualHosts = {
              loki-telemetry = (telemetryVhost 3100) // {
                locations = {
                  "= /loki/api/v1/push" = {
                    proxyPass = "http://127.0.0.1:3101";
                    extraConfig = writerOnly;
                  };
                  "= /loki/api/v1/query" = {
                    proxyPass = "http://127.0.0.1:3101";
                    extraConfig = readerOnly;
                  };
                  "= /loki/api/v1/tail" = {
                    proxyPass = "http://127.0.0.1:3101";
                    proxyWebsockets = true;
                    extraConfig = ''
                      if ($ssl_client_s_dn !~ "(^|,)CN=thornix-telemetry-reader(,|$)") {
                        return 403;
                      }
                      if ($request_method != GET) {
                        return 405;
                      }
                    '';
                  };
                  "/".return = 404;
                };
              };

              prometheus-telemetry = (telemetryVhost 9090) // {
                locations = {
                  "= /api/v1/write" = {
                    proxyPass = "http://127.0.0.1:9091";
                    extraConfig = writerOnly;
                  };
                  "= /api/v1/query" = {
                    proxyPass = "http://127.0.0.1:9091";
                    extraConfig = readerOnly;
                  };
                  "/".return = 404;
                };
              };
            };
          };

          # Avoid a first-deploy bind race: the old backends must release
          # :3100/:9090 and come back on loopback before nginx claims them.
          systemd.services.nginx = {
            wants = [
              "loki.service"
              "prometheus.service"
            ];
            after = [
              "loki.service"
              "prometheus.service"
            ];
          };

          # Prometheus TSDB backup to the NAS. Loki's chunks already live in
          # object storage, so soc has always been "rebuildable without data
          # loss" for LOGS only — metrics sat on the VM disk with no copy
          # anywhere, and a rebuild silently took 90 days of history with it.
          #
          # Backing up the data directory directly rather than enabling
          # Prometheus's admin API solely for snapshots. nginx would keep the
          # route off the network, but an unnecessary destructive API is still
          # avoidable local attack surface.
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

          # An external dead-man switch for the monitoring host itself. A
          # success ping is sent only after the local SOC services and their
          # HTTP readiness endpoints pass. Local failures are reported
          # immediately; loss of the VM, hypervisor, power, LAN, or internet
          # is detected by Healthchecks when the success pings stop.
          systemd.services.soc-deadman = {
            description = "Verify SOC health and send external heartbeat";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            path = [
              pkgs.curl
              pkgs.systemd
            ];
            script = ''
              set -u
              source ${config.sops.templates."healthchecks.env".path}

              failed=0

              systemctl is-active --quiet \
                loki prometheus grafana alloy nginx syslog || failed=1

              curl -fsS --max-time 5 \
                http://127.0.0.1:3101/ready >/dev/null || failed=1

              curl -fsS --max-time 5 \
                http://127.0.0.1:9091/-/ready >/dev/null || failed=1

              curl -fsS --max-time 5 \
                --resolve soc.guildedthorn.arpa:3000:127.0.0.1 \
                https://soc.guildedthorn.arpa:3000/api/health \
                >/dev/null || failed=1

              if (( failed != 0 )); then
                curl -fsS --retry 2 --max-time 10 \
                  "$HEALTHCHECKS_URL/fail" >/dev/null || true
                exit 1
              fi

              curl -fsS --retry 2 --max-time 10 \
                "$HEALTHCHECKS_URL" >/dev/null
            '';
            serviceConfig.Type = "oneshot";
          };

          systemd.timers.soc-deadman = {
            description = "Run SOC external heartbeat";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "2m";
              OnUnitActiveSec = "5m";
              RandomizedDelaySec = "15s";
              Unit = "soc-deadman.service";
            };
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
          # hosts/soc/networking.nix admits this port only from pfSense's
          # fixed 172.16.25.1 address; arbitrary LAN hosts cannot inject
          # records into the appliance log stream.
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

          # DNS query/reply logging is intentionally detailed and can be
          # substantially busier than the earlier IDS-only feed. Loki is the
          # durable searchable copy; keep one week of compressed raw files as
          # a short local recovery buffer instead of allowing the rsyslog
          # spool to grow without bound. HUP makes rsyslog reopen each file
          # after logrotate renames it.
          services.logrotate.settings."remote-pfsense-syslog" = {
            files = "/var/log/remote/*.log";
            frequency = "daily";
            rotate = 7;
            compress = true;
            delaycompress = true;
            dateext = true;
            missingok = true;
            notifempty = true;
            create = "0644 root root";
            postrotate = "systemctl kill --signal=HUP syslog.service >/dev/null 2>&1 || true";
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
              forward_to = [loki.process.remote_syslog.receiver]
            }

            loki.process "remote_syslog" {
              // Use the event time preserved by rsyslog. If parsing ever
              // fails, keep the entry and fall back to its file-read time.
              stage.regex {
                expression = "^(?P<pfsense_event_ts>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+(?:\\.[0-9]+)?[+-][0-9]{2}:[0-9]{2})"
              }

              stage.timestamp {
                source            = "pfsense_event_ts"
                format            = "RFC3339Nano"
                action_on_failure = "skip"
              }

              // Unbound query records:
              //   query: CLIENT QNAME QTYPE QCLASS
              // Client addresses, names, and qtypes are metadata. Although
              // qtype is protocol-defined, its 16-bit space is large enough
              // for a compromised client to churn Loki streams. Only the
              // fixed event kind becomes a label.
              stage.match {
                # Anchor on the end of Unbound's thread prefix so internal
                # verbosity-3 messages such as `info: sending query:` do not
                # inflate the client-query counters when their regex fails.
                selector      = "{job=\"syslog\"} |= \" unbound[\" |= \"] query: \""
                pipeline_name = "pfsense_unbound_query"

                stage.regex {
                  expression = "unbound\\[[0-9]+\\]: \\[[^]]+\\] query: (?P<dns_client_ip>\\S+) (?P<dns_qname>\\S+) (?P<dns_qtype_value>[A-Z0-9-]+) (?P<dns_qclass>\\S+)$"
                }

                stage.static_labels {
                  values = {
                    pfsense_log = "dns",
                    dns_event   = "query",
                  }
                }

                stage.structured_metadata {
                  values = {
                    dns_client_ip = "",
                    dns_qname     = "",
                    dns_qtype     = "dns_qtype_value",
                    dns_qclass    = "",
                  }
                }
              }

              // Unbound reply records append rcode, resolution seconds,
              // cache status (0/1), and response bytes to the query fields.
              stage.match {
                selector      = "{job=\"syslog\"} |= \" unbound[\" |= \"] reply: \""
                pipeline_name = "pfsense_unbound_reply"

                stage.regex {
                  expression = "unbound\\[[0-9]+\\]: \\[[^]]+\\] reply: (?P<dns_client_ip>\\S+) (?P<dns_qname>\\S+) (?P<dns_qtype_value>[A-Z0-9-]+) (?P<dns_qclass>\\S+) (?P<dns_rcode_value>[A-Z0-9-]+) (?P<dns_response_seconds>[0-9.]+) (?P<dns_cached_value>[01]) (?P<dns_response_bytes>[0-9]+)$"
                }

                stage.static_labels {
                  values = {
                    pfsense_log = "dns",
                    dns_event   = "reply",
                  }
                }

                stage.labels {
                  values = {
                    dns_rcode  = "dns_rcode_value",
                    dns_cached = "dns_cached_value",
                  }
                }

                stage.structured_metadata {
                  values = {
                    dns_client_ip       = "",
                    dns_qname           = "",
                    dns_qtype           = "dns_qtype_value",
                    dns_qclass          = "",
                    dns_response_seconds = "",
                    dns_response_bytes   = "",
                  }
                }
              }

              // pfSense filterlog is a documented CSV-like format. Parse
              // the common prefix once; these labels all have bounded local
              // or protocol-defined value sets. Rule identifiers, addresses,
              // ports, lengths, and header details remain metadata.
              stage.match {
                selector      = "{job=\"syslog\"} |= \" filterlog[\""
                pipeline_name = "pfsense_filterlog"

                stage.regex {
                  expression = "filterlog\\[[0-9]+\\]: (?P<firewall_rule>[^,]*),(?P<firewall_subrule>[^,]*),(?P<firewall_anchor>[^,]*),(?P<firewall_tracker>[^,]*),(?P<firewall_interface_value>[^,]*),(?P<firewall_reason>[^,]*),(?P<firewall_action_value>[^,]*),(?P<firewall_direction_value>[^,]*),(?P<firewall_ip_version_value>[46]),(?P<firewall_ip_payload>.*)$"
                }

                stage.static_labels {
                  values = { pfsense_log = "firewall" }
                }

                stage.labels {
                  values = {
                    firewall_interface  = "firewall_interface_value",
                    firewall_action     = "firewall_action_value",
                    firewall_direction  = "firewall_direction_value",
                    firewall_ip_version = "firewall_ip_version_value",
                  }
                }

                stage.structured_metadata {
                  values = {
                    firewall_rule    = "",
                    firewall_subrule = "",
                    firewall_anchor  = "",
                    firewall_tracker = "",
                    firewall_reason  = "",
                  }
                }

                // IPv4 payload: TOS, ECN, TTL, ID, fragment offset/flags,
                // protocol, packet length, source, destination, then the
                // protocol-specific tail.
                stage.match {
                  selector      = "{pfsense_log=\"firewall\", firewall_ip_version=\"4\"}"
                  pipeline_name = "pfsense_filterlog_ipv4"

                  stage.regex {
                    source     = "firewall_ip_payload"
                    expression = "(?P<firewall_tos>[^,]*),(?P<firewall_ecn>[^,]*),(?P<firewall_ttl>[^,]*),(?P<firewall_ip_id>[^,]*),(?P<firewall_fragment_offset>[^,]*),(?P<firewall_ip_flags>[^,]*),(?P<firewall_protocol_id>[^,]*),(?P<firewall_protocol_value>[^,]*),(?P<firewall_packet_length>[^,]*),(?P<geoip_src_ip>[^,]*),(?P<firewall_destination_ip>[^,]*)(?:,(?P<firewall_transport_payload>.*))?$"
                  }

                  stage.template {
                    source   = "firewall_protocol_value"
                    template = "{{ ToLower .Value }}"
                  }

                  stage.labels {
                    values = { firewall_protocol = "firewall_protocol_value" }
                  }

                  stage.structured_metadata {
                    values = {
                      firewall_tos             = "",
                      firewall_ecn             = "",
                      firewall_ttl             = "",
                      firewall_ip_id           = "",
                      firewall_fragment_offset = "",
                      firewall_ip_flags        = "",
                      firewall_protocol_id     = "",
                      firewall_packet_length   = "",
                      firewall_source_ip       = "geoip_src_ip",
                      firewall_destination_ip  = "",
                    }
                  }

                  // ix0 is this firewall's WAN. Only blocked packets entering
                  // there represent hostile external sources; enriching LAN
                  // traffic would turn the threat map into ordinary usage.
                  stage.match {
                    selector      = "{pfsense_log=\"firewall\", firewall_interface=\"ix0\", firewall_action=\"block\", firewall_direction=\"in\"}"
                    pipeline_name = "geoip_pfsense_wan_block_source"

                    stage.geoip {
                      source  = "geoip_src_ip"
                      db      = "/etc/GeoIP/DBIP-City-Lite.mmdb"
                      db_type = "city"
                    }

                    stage.geoip {
                      source  = "geoip_src_ip"
                      db      = "/etc/GeoIP/DBIP-ASN-Lite.mmdb"
                      db_type = "asn"
                    }

                    stage.static_labels {
                      values = { geoip_enriched = "true" }
                    }

                    stage.structured_metadata {
                      values = {
                        geoip_src_ip                         = "",
                        geoip_city_name                      = "",
                        geoip_country_name                   = "",
                        geoip_country_code                   = "",
                        geoip_continent_code                 = "",
                        geoip_location_latitude              = "",
                        geoip_location_longitude             = "",
                        geoip_timezone                       = "",
                        geoip_autonomous_system_number       = "",
                        geoip_autonomous_system_organization = "",
                      }
                    }
                  }
                }

                // IPv6 replaces the IPv4 header fields with traffic class,
                // flow label, and hop limit. Normalize its observed uppercase
                // protocol text before making the bounded protocol label.
                stage.match {
                  selector      = "{pfsense_log=\"firewall\", firewall_ip_version=\"6\"}"
                  pipeline_name = "pfsense_filterlog_ipv6"

                  stage.regex {
                    source     = "firewall_ip_payload"
                    expression = "(?P<firewall_traffic_class>[^,]*),(?P<firewall_flow_label>[^,]*),(?P<firewall_hop_limit>[^,]*),(?P<firewall_protocol_value>[^,]*),(?P<firewall_protocol_id>[^,]*),(?P<firewall_packet_length>[^,]*),(?P<geoip_src_ip>[^,]*),(?P<firewall_destination_ip>[^,]*)(?:,(?P<firewall_transport_payload>.*))?$"
                  }

                  stage.template {
                    source   = "firewall_protocol_value"
                    template = "{{ ToLower .Value }}"
                  }

                  stage.labels {
                    values = { firewall_protocol = "firewall_protocol_value" }
                  }

                  stage.structured_metadata {
                    values = {
                      firewall_traffic_class = "",
                      firewall_flow_label    = "",
                      firewall_hop_limit     = "",
                      firewall_protocol_id   = "",
                      firewall_packet_length = "",
                      firewall_source_ip     = "geoip_src_ip",
                      firewall_destination_ip = "",
                    }
                  }
                }

                // TCP and UDP share the first three transport fields. TCP's
                // remaining details are parsed separately below.
                stage.match {
                  selector      = "{pfsense_log=\"firewall\", firewall_protocol=~\"tcp|udp\"}"
                  pipeline_name = "pfsense_filterlog_transport"

                  stage.regex {
                    source     = "firewall_transport_payload"
                    expression = "(?P<firewall_source_port>[^,]*),(?P<firewall_destination_port>[^,]*),(?P<firewall_data_length>[^,]*)(?:,(?P<firewall_tcp_payload>.*))?$"
                  }

                  stage.structured_metadata {
                    values = {
                      firewall_source_port      = "",
                      firewall_destination_port = "",
                      firewall_data_length      = "",
                    }
                  }

                  stage.match {
                    selector      = "{pfsense_log=\"firewall\", firewall_protocol=\"tcp\"}"
                    pipeline_name = "pfsense_filterlog_tcp"

                    stage.regex {
                      source     = "firewall_tcp_payload"
                      expression = "(?P<firewall_tcp_flags>[^,]*),(?P<firewall_tcp_sequence>[^,]*),(?P<firewall_tcp_ack>[^,]*),(?P<firewall_tcp_window>[^,]*),(?P<firewall_tcp_urg>[^,]*),(?P<firewall_tcp_options>.*)$"
                    }

                    stage.structured_metadata {
                      values = {
                        firewall_tcp_flags    = "",
                        firewall_tcp_sequence = "",
                        firewall_tcp_ack      = "",
                        firewall_tcp_window   = "",
                        firewall_tcp_urg      = "",
                        firewall_tcp_options  = "",
                      }
                    }
                  }
                }
              }

              // Give every pfSense Suricata entry a bounded source-type
              // label, while leaving low-priority diagnostics searchable.
              stage.match {
                selector      = "{job=\"syslog\"} |= \" suricata\" |= \"[Priority: \""
                pipeline_name = "pfsense_suricata"

                stage.static_labels {
                  values = { pfsense_log = "suricata" }
                }
              }

              // Only Suricata priorities 1/2 enter the hostile-source map.
              stage.match {
                selector      = "{job=\"syslog\"} |= \"suricata\" |~ \"Priority: [12]\""
                pipeline_name = "geoip_pfsense_ids_source"

                stage.regex {
                  expression = "\\{[A-Z0-9]+\\}\\s+(?P<geoip_src_ip>(?:[0-9]{1,3}\\.){3}[0-9]{1,3})(?::[0-9]+)?\\s+->"
                }

                stage.geoip {
                  source  = "geoip_src_ip"
                  db      = "/etc/GeoIP/DBIP-City-Lite.mmdb"
                  db_type = "city"
                }

                stage.geoip {
                  source  = "geoip_src_ip"
                  db      = "/etc/GeoIP/DBIP-ASN-Lite.mmdb"
                  db_type = "asn"
                }

                // A single constant stream label lets dashboards select only
                // enriched findings without indexing any dynamic GeoIP data.
                stage.static_labels {
                  values = { geoip_enriched = "true" }
                }

                stage.structured_metadata {
                  values = {
                    geoip_src_ip                         = "",
                    geoip_city_name                      = "",
                    geoip_country_name                   = "",
                    geoip_country_code                   = "",
                    geoip_continent_code                 = "",
                    geoip_location_latitude              = "",
                    geoip_location_longitude             = "",
                    geoip_timezone                       = "",
                    geoip_autonomous_system_number       = "",
                    geoip_autonomous_system_organization = "",
                  }
                }
              }

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
                cert_file = telemetryServerCertificate;
                cert_key = config.sops.secrets.grafana_tls_key.path;
                enable_gzip = true;
              };
              security = {
                admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
                secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
                cookie_secure = true;
                cookie_samesite = "strict";
                disable_gravatar = true;
                strict_transport_security = true;
              };
              analytics.reporting_enabled = false;
              analytics.check_for_updates = false;
              analytics.check_for_plugin_updates = false;
              dashboards = {
                default_home_dashboard_path = "${inputs.self}/hosts/soc/dashboards/soc-overview.json";
                min_refresh_interval = "10s";
              };
              metrics.enabled = true;
              snapshots.external_enabled = false;
              users.default_theme = "dark";
              "auth.anonymous".enabled = false;
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
                  url = "http://127.0.0.1:3101";
                  jsonData.derivedFields = [
                    {
                      # Both Suricata EVE and Zeek JSON use this field. The
                      # link opens a focused dashboard panel with both data
                      # sources filtered to the exact bidirectional flow.
                      name = "Community ID";
                      # Match both raw JSON log details and the compact
                      # line_format output used by the dashboards.
                      matcherRegex = ''community_id"?\s*[:=]\s*"?([^"\s]+)'';
                      url = "/d/network-visibility/network-visibility?orgId=1&var-community_id=$${__value.raw}&from=now-6h&to=now&viewPanel=32";
                      urlDisplayLabel = "Correlate Zeek + Suricata";
                    }
                  ];
                }
                {
                  name = "Prometheus";
                  type = "prometheus";
                  uid = "prometheus";
                  url = "http://127.0.0.1:9091";
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
                            # Broad routing/search label shared by Discord
                            # notifications and Grafana's alert list.
                            category ? "operations",
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
                          expr = ''time() - node_systemd_timer_last_trigger_seconds{name="restic-backups-prometheus.timer"}'';
                          evaluator = {
                            type = "gt";
                            params = [ 129600 ];
                          };
                          for = "15m";
                          noDataState = "Alerting";
                          summary = "The Prometheus restic backup timer has not triggered in more than 36 hours.";
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
                          uid = "fleet-tls-expiry-warning";
                          title = "TLS certificate expires within 21 days";
                          datasourceUid = "prometheus";
                          expr = ''
                            (probe_ssl_earliest_cert_expiry - time() < 1814400)
                            unless
                            (probe_ssl_earliest_cert_expiry - time() < 604800)
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
                          expr = "probe_ssl_earliest_cert_expiry - time()";
                          evaluator = {
                            type = "lt";
                            params = [ 604800 ];
                          };
                          for = "5m";
                          severity = "critical";
                          summary = "A monitored HTTPS endpoint's certificate expires within seven days or has already expired.";
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
                          expr = "sum by (host) (count_over_time({job=\"systemd-journal\", unit=\"sshd.service\"} |~ \"Failed password|Invalid user\" [10m]))";
                          evaluator = {
                            type = "gt";
                            params = [ 10 ];
                          };
                          for = "0s";
                          severity = "critical";
                          category = "security";
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
                            sum(count_over_time({job="zeek", host="mac", zeek_log="notice"}
                              | json
                              | note = "SSH::Password_Guessing"
                              | dst =~ `172\.16\.25\..*` [10m]))
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
                            sum(count_over_time({job="zeek", host="mac", zeek_log="notice"}
                              | json
                              | note =~ "Heartbleed::SSL_Heartbeat_(Attack(_Success)?|Odd_Length|Many_Requests)" [10m]))
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
                          expr = "sum(count_over_time({job=\"syslog\"} |~ \"Priority: [12]\" [10m]))";
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
                          expr = ''comin_last_fetch_failed{instance=~"(nixos|proxmox|soc|websites)[.]guildedthorn[.]arpa:4243"}'';
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
          };
        }
      )
    ];
  };
}
