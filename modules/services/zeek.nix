{
  # Passive Zeek network sensor. The service reads a bridge/interface in
  # promiscuous mode, writes structured logs locally, and lets the fleet-wide
  # Alloy instance ship them to Loki. It never sits inline and cannot block
  # traffic if it fails.
  nixos.modules.services-zeek =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.zeek;

      localNetworks = lib.concatMapStringsSep "\n" (network: "  ${network},") cfg.localNetworks;

      # Zeek's X.509 verifier uses a subject -> DER table rather than an
      # OpenSSL CA bundle path. Convert the configured private trust anchor
      # into a native policy fragment at build time; the certificate is
      # public material and is already committed under certs/.
      trustedCaPolicy =
        pkgs.runCommand "thorn-zeek-trusted-ca.zeek"
          {
            nativeBuildInputs = [ pkgs.openssl ];
          }
          ''
            subject="$(openssl x509 -in ${cfg.tlsTrustAnchor} -noout -subject -nameopt RFC2253 | sed 's/^subject=//')"
            certificate="$(
              openssl x509 -in ${cfg.tlsTrustAnchor} -outform DER \
                | od -An -v -tx1 \
                | tr -d ' \n' \
                | sed 's/../\\x&/g'
            )"

            {
              printf '@load base/protocols/ssl\n\n'
              printf 'redef SSL::root_certs += {\n'
              printf '  ["%s"] = "%s",\n' "$subject" "$certificate"
              printf '};\n'
            } > "$out"
          '';

      rawPolicy = pkgs.writeText "thorn-zeek-local.zeek" ''
        # JSON keeps the original typed fields available to LogQL instead of
        # flattening everything into the legacy tab-separated representation.
        @load policy/tuning/json-logs

        # A five-minute heartbeat plus packet/drop/process counters. This is
        # what the SOC uses to distinguish a quiet network from a dead sensor.
        @load policy/misc/stats
        @load policy/misc/capture-loss

        # High-signal protocol policies. They emit notice.log records only;
        # Grafana decides which site-relevant notice types page Discord.
        @load policy/protocols/ssh/detect-bruteforcing
        @load policy/protocols/ssl/expiring-certs
        @load policy/protocols/ssl/heartbleed
        @load policy/protocols/ssl/known-certs
        @load policy/protocols/ssl/validate-certs

        # Match Suricata's Community ID so the same flow can be correlated
        # between signature alerts and Zeek's protocol/connection metadata,
        # including notices that carry an associated connection.
        @load policy/protocols/conn/community-id-logging
        @load policy/frameworks/notice/community-id
        @load policy/protocols/conn/mac-logging
        @load policy/protocols/conn/known-hosts
        @load policy/protocols/conn/known-services

        # Zeek 7 treats every RFC1918 range as local unless told otherwise.
        # This sensor intentionally protects OPT1 only; routed 192.168.1.0/24
        # clients remain remote peers in connection directionality.
        redef Site::private_address_space_is_local = F;
        redef Site::local_nets = {
        ${localNetworks}
        };

        # Alloy tails the stable current paths. Daily rotation bounds current
        # file size while leaving a long enough window for Alloy to recover
        # after a restart without racing an hourly rename.
        redef Log::default_rotation_interval = 24hrs;
        redef Log::default_rotation_dir = "rotated";
        redef LogAscii::enable_leftover_log_rotation = T;

        # stats.log is the explicit liveness source, so a traffic-free period
        # should not create a CaptureLoss::Too_Little_Traffic notice.
        redef CaptureLoss::minimum_acks = 0;

        # Thirty failures across thirty minutes is Zeek's conservative
        # upstream default and avoids paging on ordinary SSH mistakes.
        redef SSH::password_guesses_limit = 30;
        redef SSH::guessing_timeout = 30mins;

        # Certificate expiry notices are useful for services inside OPT1.
        # TLS 1.3 encrypts certificates on the wire, so these policies apply
        # only when Zeek can actually observe a certificate; blackbox probes
        # remain the authoritative direct check for known HTTPS endpoints.
        redef SSL::notify_certs_expiration = LOCAL_HOSTS;
        redef SSL::notify_when_cert_expiring_in = 30days;

        # A broken remote TLS server should not repeat the same invalid-chain
        # notice hourly forever. This changes deduplication only; the first
        # observation is still logged and available to Grafana.
        redef Notice::type_suppression_intervals += {
          [SSL::Invalid_Server_Cert] = 1day,
        };
      '';

      policyFragments = lib.optionals (cfg.tlsTrustAnchor != null) [ trustedCaPolicy ] ++ [ rawPolicy ];

      # Make policy syntax a build-time failure rather than discovering it on
      # the live hypervisor when systemd tries to start Zeek.
      checkedPolicy = pkgs.runCommand "thorn-zeek-policy" { } ''
        cat ${lib.escapeShellArgs policyFragments} > "$out"
        ${lib.getExe pkgs.zeek} -a "$out"
      '';

      zeekArgs = [
        "-i"
        cfg.interface
        # Virtio/bridge traffic can carry checksums that hardware or the
        # guest kernel has not filled in yet. Ignoring only that validation
        # keeps Zeek from discarding otherwise valid virtual traffic.
        "-C"
        # Enable Zeek's internal watchdog and expose a status file for
        # troubleshooting without a control socket or listening port.
        "-W"
        "-U"
        "/run/zeek/status"
      ]
      ++ lib.optionals (cfg.captureFilter != null) [
        "-f"
        cfg.captureFilter
      ]
      ++ [ checkedPolicy ];

      zeekStart = pkgs.writeShellScript "zeek-start" ''
        exec ${lib.getExe pkgs.zeek} ${lib.escapeShellArgs zeekArgs}
      '';

      # conn.log can contain far more individual flows than Prometheus should
      # retain as time-series labels. This small local process reduces it to
      # a fixed-size, rolling host graph before node_exporter exposes it.
      topologyExporter = pkgs.writeTextFile {
        name = "thorn-zeek-topology-exporter";
        destination = "/bin/thorn-zeek-topology-exporter";
        executable = true;
        text = ''
          #!${lib.getExe pkgs.python3}
          ${builtins.readFile ./zeek-topology-exporter.py}
        '';
      };
      topologyKnownHosts = pkgs.writeText "thorn-zeek-topology-known-hosts.json" (
        builtins.toJSON cfg.topology.knownHosts
      );
      topologyMetricsDirectory = "/run/thorn-topology";
      topologyMetricsFile = "${topologyMetricsDirectory}/topology.prom";
      topologyArgs = [
        "--input"
        "/var/log/zeek/conn.log"
        "--output"
        topologyMetricsFile
        "--known-hosts"
        topologyKnownHosts
        "--window-seconds"
        (toString cfg.topology.windowSeconds)
        "--bucket-seconds"
        (toString cfg.topology.bucketSeconds)
        "--max-nodes"
        (toString cfg.topology.maxNodes)
        "--max-edges"
        (toString cfg.topology.maxEdges)
        "--render-interval"
        (toString cfg.topology.renderIntervalSeconds)
      ]
      ++ lib.concatMap (network: [
        "--local-network"
        network
      ]) cfg.localNetworks;
    in
    {
      options.thorn.zeek = {
        enable = lib.mkEnableOption "a passive Zeek network sensor";

        interface = lib.mkOption {
          type = lib.types.str;
          default = "vmbr0";
          description = "Interface or bridge Zeek captures in promiscuous mode.";
        };

        localNetworks = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "172.16.25.0/24" ];
          description = "Networks Zeek classifies as local/protected.";
        };

        tlsTrustAnchor = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Optional PEM root certificate added to Zeek's native TLS trust
            table for passive certificate validation. Mozilla roots remain
            enabled; this adds a private/internal CA alongside them.
          '';
        };

        captureFilter = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "not (host 172.16.25.3 and host 172.16.25.51 and tcp port 3100)";
          description = ''
            Optional libpcap filter. Use this to exclude the sensor's own
            Alloy-to-Loki flow, which would otherwise turn every shipped Zeek
            HTTP log into another Zeek HTTP log and create an ingestion loop.
          '';
        };

        topology = {
          enable = lib.mkEnableOption "a bounded live topology export from Zeek conn.log";

          windowSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 300;
            description = "Rolling window represented by the live topology graph.";
          };

          bucketSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 10;
            description = "Internal aggregation bucket size.";
          };

          renderIntervalSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 5;
            description = "How often the node_exporter textfile snapshot is replaced.";
          };

          maxNodes = lib.mkOption {
            type = lib.types.ints.positive;
            default = 128;
            description = "Maximum nodes rendered at once.";
          };

          maxEdges = lib.mkOption {
            type = lib.types.ints.positive;
            default = 256;
            description = "Maximum directed edges retained and rendered at once.";
          };

          knownHosts = lib.mkOption {
            default = { };
            description = ''
              Stable labels for known IPs. Unknown addresses inside localNetworks
              retain their IP; public and non-local private peers are aggregated
              so hostile traffic cannot create unbounded Prometheus cardinality.
            '';
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  title = lib.mkOption {
                    type = lib.types.nonEmptyStr;
                    description = "Unique short node title and graph identifier.";
                  };
                  role = lib.mkOption {
                    type = lib.types.nonEmptyStr;
                    default = "discovered";
                    description = "Displayed asset role.";
                  };
                  color = lib.mkOption {
                    type = lib.types.str;
                    default = "";
                    description = "Optional Grafana color name; role color is used when empty.";
                  };
                };
              }
            );
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.interface != "";
            message = "thorn.zeek.interface must name a capture interface";
          }
          {
            assertion = cfg.localNetworks != [ ];
            message = "thorn.zeek.localNetworks must contain at least one subnet";
          }
        ]
        ++ lib.optionals cfg.topology.enable [
          {
            assertion = cfg.topology.windowSeconds >= cfg.topology.bucketSeconds * 2;
            message = "thorn.zeek.topology.windowSeconds must contain at least two buckets";
          }
          {
            assertion = cfg.topology.maxNodes >= 2;
            message = "thorn.zeek.topology.maxNodes must be at least two";
          }
        ];

        environment.systemPackages = [ pkgs.zeek ];

        users.groups.zeek = { };
        users.users.zeek = {
          isSystemUser = true;
          group = "zeek";
          description = "Zeek network sensor";
        };
        users.groups.zeek-topology = lib.mkIf cfg.topology.enable { };
        users.users.zeek-topology = lib.mkIf cfg.topology.enable {
          isSystemUser = true;
          group = "zeek-topology";
          description = "Bounded Zeek topology exporter";
        };

        systemd.services.zeek = {
          description = "Zeek passive network security monitor";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = zeekStart;
            Restart = "on-failure";
            RestartSec = "5s";
            TimeoutStopSec = "30s";

            User = "zeek";
            Group = "zeek";
            UMask = "0027";
            WorkingDirectory = "/var/log/zeek";
            LogsDirectory = "zeek";
            LogsDirectoryMode = "0750";
            StateDirectory = "zeek";
            StateDirectoryMode = "0750";
            RuntimeDirectory = "zeek";
            RuntimeDirectoryMode = "0750";

            # Opening an AF_PACKET socket and enabling promiscuous membership
            # require these capabilities; Zeek otherwise runs unprivileged.
            AmbientCapabilities = [
              "CAP_NET_ADMIN"
              "CAP_NET_RAW"
            ];
            CapabilityBoundingSet = [
              "CAP_NET_ADMIN"
              "CAP_NET_RAW"
            ];
            NoNewPrivileges = true;

            # A parser bug or traffic spike must not contend with guests for
            # the whole hypervisor. Two full cores and 4 GiB are ample for the
            # measured homelab traffic and can be raised later from evidence.
            CPUQuota = "200%";
            MemoryMax = "4G";
            Nice = 10;
            IOSchedulingClass = "idle";

            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictRealtime = true;
            LockPersonality = true;
            SystemCallArchitectures = "native";
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_PACKET"
              "AF_INET"
              "AF_INET6"
              "AF_NETLINK"
            ];
          };
        };

        systemd.services.zeek-topology-exporter = lib.mkIf cfg.topology.enable {
          description = "Bounded live network topology exporter";
          wantedBy = [ "multi-user.target" ];
          wants = [ "zeek.service" ];
          after = [ "zeek.service" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${topologyExporter}/bin/thorn-zeek-topology-exporter ${lib.escapeShellArgs topologyArgs}";
            Restart = "on-failure";
            RestartSec = "5s";
            CPUQuota = "25%";
            MemoryMax = "256M";
            TasksMax = 32;
            Nice = 15;
            IOSchedulingClass = "idle";

            # A separate identity gets read-only group access to Zeek logs and
            # writes only its node_exporter textfile runtime directory. This is
            # static rather than DynamicUser because node_exporter must be able
            # to traverse and read the generated public metrics file.
            User = "zeek-topology";
            Group = "zeek-topology";
            SupplementaryGroups = [ "zeek" ];
            RuntimeDirectory = "thorn-topology";
            RuntimeDirectoryMode = "0755";
            UMask = "0022";

            NoNewPrivileges = true;
            CapabilityBoundingSet = "";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            PrivateNetwork = true;
            IPAddressDeny = "any";
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            ProtectClock = true;
            ProtectHostname = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            RestrictSUIDSGID = true;
            RestrictRealtime = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            SystemCallArchitectures = "native";
            RestrictAddressFamilies = [ "AF_UNIX" ];
          };
        };

        # Reuse the already SOC-restricted node_exporter listener rather than
        # opening another HTTP port on the hypervisor. The exporter atomically
        # replaces this file every five seconds.
        services.prometheus.exporters.node = lib.mkIf cfg.topology.enable {
          enabledCollectors = [ "textfile" ];
          extraFlags = [ "--collector.textfile.directory=${topologyMetricsDirectory}" ];
        };

        # Rotated files are only a local recovery buffer; Loki remains the
        # 90-day source of truth. Current files are never age-cleaned while
        # Zeek has them open.
        systemd.tmpfiles.rules = [
          "d /var/log/zeek/rotated 0750 zeek zeek 7d"
        ];

        # Alloy's DynamicUser receives read-only group access to Zeek logs.
        systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "zeek" ];

        environment.etc."alloy/zeek.alloy".text = ''
          local.file_match "zeek" {
            path_targets = [{
              "__path__" = "/var/log/zeek/*.log",
              job        = "zeek",
              host       = "${config.networking.hostName}",
              sensor     = "${cfg.interface}",
            }]
          }

          loki.source.file "zeek" {
            targets    = local.file_match.zeek.targets
            forward_to = [loki.relabel.zeek.receiver]
          }

          // Turn /var/log/zeek/conn.log into the bounded zeek_log="conn"
          // label. The field is a stream type, not an address/UID, so it
          // cannot create unbounded Loki label cardinality.
          loki.relabel "zeek" {
            forward_to = [loki.process.zeek.receiver]

            rule {
              source_labels = ["filename"]
              regex         = ".*/([^.]+)\\.log"
              replacement   = "$1"
              target_label  = "zeek_log"
            }
          }

          loki.process "zeek" {
            // Preserve packet/event time instead of using Alloy's file-read
            // time, which matters if buffered logs catch up after an outage.
            stage.json {
              expressions    = { event_ts = "ts" }
              drop_malformed = true
            }

            stage.timestamp {
              source            = "event_ts"
              format            = "Unix"
              action_on_failure = "skip"
            }

            forward_to = [loki.write.soc.receiver]
          }
        '';
      };
    };
}
