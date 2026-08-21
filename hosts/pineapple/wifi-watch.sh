#!/bin/sh

TARGET_BSSID="80:af:ca:23:c6:c8"
TARGET_SSID="ThornCloud"
MONITOR_INTERFACE="wlan1"
SCAN_INTERFACE="wlan3"
CHANNEL="8"
WINDOW_SECONDS="10"
DEAUTH_THRESHOLD="5"
ALERT_COOLDOWN="60"
ROGUE_SCAN_INTERVAL="300"
HEARTBEAT_INTERVAL="300"
ALERT_URL="https://mitm.guildedthorn.arpa/pineapple-wifi-watch"
CA_CERT="/etc/ssl/certs/ThornCloud_CA.crt"
STATE_DIR="/tmp/wifi-watch"

mkdir -p "$STATE_DIR"

send_alert() {
	event="$1"
	message="$2"
	payload="$STATE_DIR/alert.json"

	printf '{"event":"%s","message":"%s"}\n' "$event" "$message" >"$payload"
	logger -p auth.warn -t wifi-watch "$message"
	uclient-fetch --quiet --timeout=10 --ca-certificate="$CA_CERT" \
		--post-file="$payload" -O /dev/null "$ALERT_URL" ||
		logger -p auth.err -t wifi-watch "Failed to deliver Home Assistant alert"
}

if [ "${1:-}" = "--test-alert" ]; then
	send_alert "test" "Pineapple passive wireless monitor test"
	exit
fi

last_deauth_alert=0
last_rogue_scan=0
last_heartbeat=0
capture_pid=""

cleanup() {
	if [ -n "$capture_pid" ]; then
		kill "$capture_pid" 2>/dev/null
		wait "$capture_pid" 2>/dev/null
	fi
	exit
}

trap cleanup INT TERM

while ! ip link show "$MONITOR_INTERFACE" >/dev/null 2>&1 ||
	! ip link show "$SCAN_INTERFACE" >/dev/null 2>&1; do
	sleep 2
done

ip link set "$MONITOR_INTERFACE" up
ip link set "$SCAN_INTERFACE" up

while true; do
	iw dev "$MONITOR_INTERFACE" set channel "$CHANNEL"
	frames="$STATE_DIR/deauth.frames"

	tcpdump -i "$MONITOR_INTERFACE" -nn -l -e \
		"(type mgt subtype deauth or type mgt subtype disassoc) and (wlan addr1 $TARGET_BSSID or wlan addr2 $TARGET_BSSID or wlan addr3 $TARGET_BSSID)" \
		>"$frames" 2>/dev/null &
	capture_pid="$!"
	sleep "$WINDOW_SECONDS"
	kill "$capture_pid" 2>/dev/null
	wait "$capture_pid" 2>/dev/null
	capture_pid=""

	count="$(wc -l <"$frames")"
	now="$(date +%s)"

	if [ $((now - last_heartbeat)) -ge "$HEARTBEAT_INTERVAL" ]; then
		logger -p daemon.info -t wifi-watch "heartbeat bssid=$TARGET_BSSID channel=$CHANNEL"
		last_heartbeat="$now"
	fi

	if [ "$count" -ge "$DEAUTH_THRESHOLD" ] && [ $((now - last_deauth_alert)) -ge "$ALERT_COOLDOWN" ]; then
		send_alert "deauth_flood" "Wi-Fi alert: $count deauth/disassoc frames targeted ThornCloud in ${WINDOW_SECONDS}s"
		last_deauth_alert="$now"
	fi

	if [ $((now - last_rogue_scan)) -ge "$ROGUE_SCAN_INTERVAL" ]; then
		rogues="$STATE_DIR/rogue-bssids"
		previous="$STATE_DIR/rogue-bssids.previous"

		iw dev "$SCAN_INTERFACE" scan passive 2>/dev/null |
			awk -v trusted="$TARGET_BSSID" -v ssid="$TARGET_SSID" '
        /^BSS / {
          bssid = tolower($2)
          sub(/\(.*/, "", bssid)
        }
        $1 == "SSID:" {
          current = substr($0, index($0, "SSID:") + 6)
          if (current == ssid && bssid != trusted) print bssid
        }
      ' | sort -u >"$rogues"

		if [ -s "$rogues" ] && ! cmp -s "$rogues" "$previous"; then
			rogue_list="$(tr '\n' ',' <"$rogues" | sed 's/,$//')"
			send_alert "rogue_ap" "Wi-Fi alert: untrusted BSSID advertising ThornCloud: $rogue_list"
		fi

		cp "$rogues" "$previous"
		last_rogue_scan="$now"
	fi
done
