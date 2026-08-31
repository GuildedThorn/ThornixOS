{
  lib,
  pkgs,
  ...
}:
{
  # Kea's module creates a static account, but DynamicUser places its control
  # socket in a private mount namespace that the unprivileged exporter cannot
  # access. Keep both processes on the static kea user instead.
  systemd.services.kea-dhcp4-server.serviceConfig.DynamicUser = lib.mkForce false;

  systemd.services.firewall-health-metrics = {
    description = "Export firewall health metrics for node_exporter";
    serviceConfig = {
      Type = "oneshot";
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/node-exporter-textfiles" ];
    };
    path = with pkgs; [
      bind
      coreutils
      gawk
      gnugrep
      iproute2
      nftables
      systemd
      wireguard-tools
    ];
    script = ''
      set -o errexit -o nounset -o pipefail

      output=/var/lib/node-exporter-textfiles/firewall-health.prom
      temporary=$(mktemp "''${output}.tmp.XXXXXX")
      trap 'rm -f "$temporary"' EXIT

      {
        printf '# HELP thorn_firewall_health_collector_success Whether firewall health collection completed successfully.\n'
        printf '# TYPE thorn_firewall_health_collector_success gauge\n'

        lease_file=/var/lib/kea/dhcp4.leases
        if [[ -r "$lease_file" ]]; then
          printf '# HELP thorn_firewall_dhcp_active_leases Active Kea DHCP leases by subnet.\n'
          printf '# TYPE thorn_firewall_dhcp_active_leases gauge\n'
          awk -F, '
            NR == 1 {
              for (i = 1; i <= NF; i++) {
                if ($i == "subnet_id") subnet = i
                if ($i == "state") state = i
              }
              next
            }
            subnet && state && $state == 0 { leases[$subnet]++ }
            END {
              printf "thorn_firewall_dhcp_active_leases{subnet_id=\"1\"} %d\n", leases[1] + 0
              printf "thorn_firewall_dhcp_active_leases{subnet_id=\"2\"} %d\n", leases[2] + 0
            }
          ' "$lease_file"
          printf 'thorn_firewall_health_collector_success 1\n'
        else
          printf 'thorn_firewall_health_collector_success 0\n'
        fi

        printf '# HELP thorn_firewall_dhcp_pool_capacity Configured Kea dynamic pool capacity.\n'
        printf '# TYPE thorn_firewall_dhcp_pool_capacity gauge\n'
        printf 'thorn_firewall_dhcp_pool_capacity{subnet_id="1"} 225\n'
        printf 'thorn_firewall_dhcp_pool_capacity{subnet_id="2"} 100\n'

        printf '# HELP thorn_firewall_wireguard_latest_handshake_seconds Unix time of each WireGuard peer latest handshake.\n'
        printf '# TYPE thorn_firewall_wireguard_latest_handshake_seconds gauge\n'
        wg show wg0 dump | awk '
          NR > 1 {
            sub("/32$", "", $4)
            printf "thorn_firewall_wireguard_latest_handshake_seconds{peer=\"%s\"} %d\n", $4, $5
          }
        '

        printf '# HELP thorn_firewall_watchdog_success Whether an active firewall check succeeded.\n'
        printf '# TYPE thorn_firewall_watchdog_success gauge\n'
        for unit in kea-dhcp4-server unbound nftables systemd-networkd; do
          if systemctl is-active --quiet "$unit.service"; then
            printf 'thorn_firewall_watchdog_success{check="service-%s"} 1\n' "$unit"
          else
            printf 'thorn_firewall_watchdog_success{check="service-%s"} 0\n' "$unit"
          fi
        done
        if dig +time=3 +tries=1 @127.0.0.1 . SOA >/dev/null; then
          printf 'thorn_firewall_watchdog_success{check="dns-recursion"} 1\n'
        else
          printf 'thorn_firewall_watchdog_success{check="dns-recursion"} 0\n'
        fi
        if ip route get 1.1.1 | grep -q 'dev wan'; then
          printf 'thorn_firewall_watchdog_success{check="wan-route"} 1\n'
        else
          printf 'thorn_firewall_watchdog_success{check="wan-route"} 0\n'
        fi
        if nft list table inet thorn-egress >/dev/null; then
          printf 'thorn_firewall_watchdog_success{check="egress-policy"} 1\n'
        else
          printf 'thorn_firewall_watchdog_success{check="egress-policy"} 0\n'
        fi
      } > "$temporary"

      chmod 0644 "$temporary"
      mv -f "$temporary" "$output"
      trap - EXIT
    '';
  };

  systemd.services.unbound-exporter = {
    description = "Prometheus exporter for Unbound";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "unbound.service"
    ];
    requires = [ "unbound.service" ];
    serviceConfig = {
      User = "unbound";
      Group = "unbound";
      ExecStart = lib.escapeShellArgs [
        "${pkgs.prometheus-unbound-exporter}/bin/unbound_exporter"
        "-unbound.ca="
        "-unbound.cert="
        "-unbound.key="
        "-unbound.host=unix:///run/unbound/unbound.ctl"
        "-web.listen-address=172.16.25.1:9167"
      ];
      DynamicUser = false;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.kea-exporter = {
    description = "Prometheus exporter for Kea DHCP";
    wantedBy = [ "multi-user.target" ];
    after = [ "kea-dhcp4-server.service" ];
    requires = [ "kea-dhcp4-server.service" ];
    serviceConfig = {
      User = "kea";
      Group = "kea";
      ExecStart = lib.escapeShellArgs [
        "${pkgs.prometheus-kea-exporter}/bin/kea-exporter"
        "--address"
        "172.16.25.1"
        "--port"
        "9547"
        "--interval"
        "10"
        "/run/kea/kea4-ctrl-socket"
      ];
      DynamicUser = false;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.timers.firewall-health-metrics = {
    description = "Refresh firewall health metrics";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
      AccuracySec = "15s";
      Unit = "firewall-health-metrics.service";
    };
  };
}
