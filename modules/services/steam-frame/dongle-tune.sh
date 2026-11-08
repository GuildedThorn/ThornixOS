# shellcheck shell=bash

# Disable the rtw89 "inactive power save" feature for the Steam Frame wireless
# adapter (USB 28de:2432, Realtek RTL8852CU, driver rtw89_8852cu).
#
# The chip keeps entering a low-power state between scans. Waking it up again
# takes several seconds and happens on the USB bus while the kernel holds RTNL,
# so the whole desktop freezes. Setting RTW89_DM_INACTIVE_PS in the driver's
# disable_dm bitmap stops it.
#
# This runs as a udev-triggered oneshot, so the netdev name is passed as $1.
# Non-critical failures exit 0: the headset link still works, it is only slower,
# and a failing unit would mark the boot degraded for no actionable reason.

if [[ $# -ne 1 ]]; then
	echo "usage: $0 <interface>" >&2
	exit 2
fi

readonly iface=$1
readonly phy_link="/sys/class/net/${iface}/phy80211"
readonly dm_bit=$((1 << 5)) # RTW89_DM_INACTIVE_PS

# systemd mounts debugfs early, but do not assume it on unusual setups.
if [[ ! -d /sys/kernel/debug/ieee80211 ]]; then
	mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
fi

# The phy and its debugfs directory appear asynchronously after the USB device
# probes. Firmware loading alone can take a few seconds on this chip.
phy=""
for _ in $(seq 1 30); do
	if [[ -e ${phy_link} ]]; then
		phy=$(basename "$(readlink -f "${phy_link}")")
		break
	fi
	sleep 1
done

if [[ -z ${phy} ]]; then
	echo "no phy80211 for ${iface}; nothing to tune" >&2
	exit 0
fi

readonly dm_file="/sys/kernel/debug/ieee80211/${phy}/rtw89/disable_dm"

for _ in $(seq 1 20); do
	[[ -w ${dm_file} ]] && break
	sleep 1
done

if [[ ! -w ${dm_file} ]]; then
	echo "${dm_file} is not writable; kernel needs CONFIG_RTW89_DEBUGFS=y" >&2
	exit 0
fi

read_dm() {
	grep -oE '0x[0-9a-fA-F]+' "${dm_file}" | head -n 1
}

current=$(read_dm || true)
if [[ -z ${current} ]]; then
	echo "cannot parse current value from ${dm_file}" >&2
	exit 0
fi

# Keep every other bit and set RTW89_DM_INACTIVE_PS.
printf '0x%x\n' $((current | dm_bit)) >"${dm_file}"

after=$(read_dm || true)
if [[ -z ${after} ]] || (((after & dm_bit) == 0)); then
	echo "inactive power save still enabled (disable_dm=${after:-unreadable})" >&2
	exit 1
fi

# Redundant with the NetworkManager powersave setting, but this also applies
# when the interface is brought up outside NetworkManager.
iw dev "${iface}" set power_save off >/dev/null 2>&1 || true

echo "${iface} (${phy}): inactive power save disabled (disable_dm ${after})"
