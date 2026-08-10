{
  nixos.modules.services-ksm =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.ksm;
    in
    {
      options.thorn.ksm = {
        enable = lib.mkEnableOption "adaptive Kernel Same-page Merging for a trusted VM host";

        advisor = {
          maxCpuPercent = lib.mkOption {
            type = lib.types.ints.between 1 100;
            default = 10;
            description = "Maximum CPU percentage the KSM scan-time advisor may consume.";
          };

          targetScanTimeSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 600;
            description = "Target time in seconds for one complete scan of mergeable memory.";
          };

          minPagesToScan = lib.mkOption {
            type = lib.types.ints.positive;
            default = 500;
            description = "Minimum pages the KSM advisor may inspect in one scan batch.";
          };

          maxPagesToScan = lib.mkOption {
            type = lib.types.ints.positive;
            default = 30000;
            description = "Maximum pages the KSM advisor may inspect in one scan batch.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.advisor.minPagesToScan <= cfg.advisor.maxPagesToScan;
            message = "thorn.ksm.advisor.minPagesToScan must not exceed maxPagesToScan";
          }
        ];

        # Use the upstream NixOS switch so this composes with future kernel and
        # module changes, then replace its fixed run=1 script with the kernel's
        # adaptive scan-time advisor. QEMU marks ordinary guest RAM mergeable
        # by default, so this single host service covers every VM on mac.
        hardware.ksm.enable = true;

        systemd.services.enable-ksm = {
          before = [ "pve-guests.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            CapabilityBoundingSet = "";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateNetwork = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectSystem = "strict";
            RestrictAddressFamilies = [ "AF_UNIX" ];
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
          };

          script = lib.mkForce ''
            set -o errexit -o nounset -o pipefail

            ksm=/sys/kernel/mm/ksm
            for knob in \
              run advisor_mode advisor_max_cpu advisor_target_scan_time \
              advisor_min_pages_to_scan advisor_max_pages_to_scan smart_scan
            do
              if [[ ! -w "$ksm/$knob" ]]; then
                echo "adaptive KSM requires writable $ksm/$knob" >&2
                exit 1
              fi
            done

            # Pause scanning without discarding already-shared pages while a
            # generation switch retunes the advisor.
            printf '0\n' > "$ksm/run"
            printf '%s\n' ${toString cfg.advisor.maxCpuPercent} > "$ksm/advisor_max_cpu"
            printf '%s\n' ${toString cfg.advisor.targetScanTimeSeconds} > "$ksm/advisor_target_scan_time"
            printf '%s\n' ${toString cfg.advisor.minPagesToScan} > "$ksm/advisor_min_pages_to_scan"
            printf '%s\n' ${toString cfg.advisor.maxPagesToScan} > "$ksm/advisor_max_pages_to_scan"
            printf '1\n' > "$ksm/smart_scan"
            printf 'scan-time\n' > "$ksm/advisor_mode"
            printf '1\n' > "$ksm/run"
          '';

          # When this module is disabled, discard shared mappings rather than
          # silently leaving KSM savings (and its cross-VM side-channel) live.
          preStop = ''
            if [[ -w /sys/kernel/mm/ksm/run ]]; then
              printf '2\n' > /sys/kernel/mm/ksm/run
            fi
          '';
        };

        # node_exporter reads the bounded set of numeric KSM sysfs counters.
        # The existing SOC-only firewall remains the only network exposure.
        services.prometheus.exporters.node.enabledCollectors = [ "ksmd" ];
      };
    };
}
