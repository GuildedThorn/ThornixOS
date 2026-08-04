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

      rawPolicy = pkgs.writeText "thorn-zeek-local.zeek" ''
        # JSON keeps the original typed fields available to LogQL instead of
        # flattening everything into the legacy tab-separated representation.
        @load policy/tuning/json-logs

        # A five-minute heartbeat plus packet/drop/process counters. This is
        # what the SOC uses to distinguish a quiet network from a dead sensor.
        @load policy/misc/stats
        @load policy/misc/capture-loss

        # Match Suricata's Community ID so the same flow can be correlated
        # between signature alerts and Zeek's protocol/connection metadata.
        @load policy/protocols/conn/community-id-logging
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
      '';

      # Make policy syntax a build-time failure rather than discovering it on
      # the live hypervisor when systemd tries to start Zeek.
      checkedPolicy = pkgs.runCommand "thorn-zeek-policy" { } ''
        ${lib.getExe pkgs.zeek} -a ${rawPolicy}
        cp ${rawPolicy} "$out"
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
        ];

        environment.systemPackages = [ pkgs.zeek ];

        users.groups.zeek = { };
        users.users.zeek = {
          isSystemUser = true;
          group = "zeek";
          description = "Zeek network sensor";
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
