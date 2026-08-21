# WiFi Pineapple Mark VII

Permanent passive wireless sensor at `192.168.1.31`.

- `wlan1` stays on ThornCloud's primary 2.4 GHz channel and detects bursts of
  deauthentication/disassociation frames targeting its BSSID.
- `wlan3` performs periodic passive surveys and alerts when an untrusted BSSID
  advertises the exact `ThornCloud` SSID.
- Detection logs locally through syslog and posts source-restricted alerts to
  Home Assistant.
- OpenWrt forwards syslog to SOC on `172.16.25.51:5514/tcp`; `wifi-watch`
  emits a five-minute heartbeat so Grafana can distinguish quiet from dead.
- No PineAP injection, deauthentication, Karma, beacon response, or SSID
  impersonation feature is required or enabled by this monitor.

Runtime files:

```text
/usr/sbin/wifi-watch
/etc/init.d/wifi-watch
/etc/ssl/certs/ThornCloud_CA.crt
```

OpenSSH uses key-only root access with `hosts/pineapple/sshd_config`; password
and keyboard-interactive authentication are disabled.
