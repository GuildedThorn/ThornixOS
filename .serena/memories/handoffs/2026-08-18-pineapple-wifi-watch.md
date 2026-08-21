# WiFi Pineapple permanent passive monitor

## Live appliance
- Host: `root@192.168.1.31`, Hak5 WiFi Pineapple Mark VII, OpenWrt 21.02.1, kernel 5.4.154, PineAP 5.0.
- SSH now key-only with `/home/thorn/.ssh/id_ed25519`. Password and keyboard-interactive auth disabled. Do not store old password.
- Temporary known-host file: `/tmp/opencode/pineapple_known_hosts`; recreate/trust after local reboot.
- Management uplink: wlan2 associated to ThornCloud. Trusted BSSID `80:af:ca:23:c6:c8`, primary channel 8.
- `wlan1`: monitor mode, fixed channel 8.
- `wlan3`: spare managed radio used for passive scans every 5 minutes.
- Hidden open AP on wlan0 disabled.
- PineAP daemon disabled/inactive. No Karma, beacon responses, broadcast pool, capture SSIDs, deauth, injection, or impersonation features used.

## Detector
- Repo files: `hosts/pineapple/wifi-watch.sh`, `wifi-watch.init`, `sshd_config`, `README.md`.
- Runtime files: `/usr/sbin/wifi-watch`, `/etc/init.d/wifi-watch`, `/etc/ssh/sshd_config`, `/etc/ssl/certs/ThornCloud_CA.crt`.
- Init enabled at `/etc/rc.d/S95wifi-watch`; reboot tested.
- Deauth/disassoc rule: alert at >=5 target frames in 10 seconds, 60-second cooldown.
- Rogue rule: passive wlan3 scan every 300 seconds; alert if exact SSID `ThornCloud` appears on BSSID other than `80:af:ca:23:c6:c8`.
- Logs locally through syslog tag `wifi-watch`.
- Home Assistant alert receiver: source-restricted nginx endpoint `https://mitm.guildedthorn.arpa/pineapple-wifi-watch`, allowed only from `192.168.1.31`, proxied to local HA webhook.
- HA automation entity: `automation.pineapple_wireless_security_alert`; creates persistent notification.
- End-to-end `wifi-watch --test-alert` passed. Test log at 2026-08-18 23:24:03.
- Current baseline: zero deauth/disassoc target frames, zero rogue BSSIDs.
- Resource use healthy after reboot: about 177 MB available RAM, no swap.

## Verification
- `wifi-watch` and child `tcpdump` active after reboot.
- wlan1 remains monitor channel 8.
- wlan2 reconnects to trusted BSSID.
- PineAP remains inactive and wlan0 AP absent.
- Remote/runtime hashes matched repo files.
- Shellcheck and `git diff --check` passed; MITM NixOS build/deploy passed.

## SOC telemetry
- Pineapple forwards OpenWrt syslog to SOC `172.16.25.51:5514/tcp`; `system.@system[0].log_proto=tcp` is committed in UCI.
- UDP transit through Pineapple wlan2/pfSense path duplicated packets: one source egress packet became two SOC ingress packets. TCP removed duplicate log entries; test marker produced exactly one raw rsyslog line and one Loki event.
- SOC rsyslog listens on both UDP 5514 for pfSense and TCP 5514 for Pineapple. Firewall allows each protocol only from its appliance source.
- Alloy labels `/var/log/remote/192.168.1.31.log` as `{job="syslog", host="pineapple"}`.
- Grafana dashboard UID `wireless-security`; alert rule UIDs `siem-pineapple-wireless-alert` and `siem-pineapple-heartbeat-silent`. API checks returned 200 after final deployment.
- Dashboard JSON is currently untracked, so normal git-backed flake evaluation excludes it until committed. It was restored through Grafana API after deployment; commit `hosts/soc/dashboards/wireless-security.json` before relying on future provisioning.

## Caveats
- Coverage is only ThornCloud 2.4 GHz primary channel 8. Add MK7AC/dedicated monitor for 5 GHz.
- Firmware SSH lacks post-quantum KEX due age. Key-only access mitigates credential exposure but firmware update should be planned; Hak5 firmware update may overwrite runtime files, so redeploy from repo afterward.
- Monitor detects frame-rate anomalies, not non-802.11 RF jamming.
