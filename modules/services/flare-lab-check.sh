# shellcheck shell=bash

# Compare the live Proxmox configuration of the FLARE detonation lab VMs
# against the inventory this repo declares.
#
# The lab VMs are built and snapshotted by hand, so their configuration exists
# only in /etc/pve on the hypervisor and is invisible to nixos-rebuild. The
# guest-agent flag is the important one: every piece of detonation automation
# goes through it, and nothing in Git records that it is supposed to be set. If
# it is ever cleared, the symptom is a control channel that reports every VM as
# unreachable with no explanation recorded anywhere. This turns that silent
# break into a logged one.

set -euo pipefail

CONF_DIR=${FLARE_LAB_CONF_DIR:-/etc/pve/qemu-server}
INVENTORY=${FLARE_LAB_INVENTORY:-/etc/flare-lab/inventory.json}
verbose=0

usage() {
	cat <<'EOF'
Check the FLARE lab VMs against their declared inventory.

Usage:
  flare-lab-check [--inventory <path>] [--conf-dir <path>] [--verbose]

Options:
  --inventory <path>   JSON inventory keyed by vmid.
                       Default /etc/flare-lab/inventory.json
  --conf-dir <path>    Directory holding <vmid>.conf.
                       Default /etc/pve/qemu-server
  -v, --verbose        Report every field, not just the ones that differ.
  -h, --help           Show this help.

Exits non-zero when the live configuration differs from the inventory.
EOF
}

while (($# > 0)); do
	case $1 in
	--inventory)
		shift
		(($# > 0)) || {
			printf 'error: --inventory needs a value\n' >&2
			exit 2
		}
		INVENTORY=$1
		;;
	--conf-dir)
		shift
		(($# > 0)) || {
			printf 'error: --conf-dir needs a value\n' >&2
			exit 2
		}
		CONF_DIR=$1
		;;
	-v | --verbose) verbose=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf 'error: unknown option: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done

[[ -r $INVENTORY ]] || {
	printf 'error: cannot read inventory: %s\n' "$INVENTORY" >&2
	exit 2
}

# Read one "key: value" line out of a Proxmox VM config. The format is flat
# with at most one of each key, and the key must start the line, so that
# looking up "agent" cannot match a line beginning "agentfoo".
conf_get() {
	local file=$1 key=$2
	awk -v k="$key" 'index($0, k ":") == 1 { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' "$file"
}

# Net device options are a comma-separated list, so a field is pulled out by
# splitting on commas rather than by pattern-matching the whole line.
net_field() {
	local net=$1 want=$2
	tr ',' '\n' <<<"$net" | awk -F= -v w="$want" '$1 == w { print $2; exit }'
}

drift=0
checked=0

# Compare one declared field against the live value. The counter is bumped in
# this shell rather than a subshell so it survives the call.
check() {
	local label=$1 want=$2 got=$3
	checked=$((checked + 1))
	if [[ $want == "$got" ]]; then
		if ((verbose)); then
			printf '  ok      %-14s %s\n' "$label" "$got"
		fi
		return 0
	fi
	printf '  DRIFT   %-14s declared %s, live %s\n' "$label" "$want" "$got"
	drift=$((drift + 1))
}

mapfile -t vmids < <(jq -r 'keys[]' "$INVENTORY" | sort -n)
((${#vmids[@]} > 0)) || {
	printf 'error: inventory declares no VMs: %s\n' "$INVENTORY" >&2
	exit 2
}

printf 'FLARE lab inventory check against %s\n' "$CONF_DIR"
for vmid in "${vmids[@]}"; do
	conf=$CONF_DIR/$vmid.conf
	# The dollar in $v has to survive bash to reach jq, where it names the
	# argument passed below. Unescaped it would expand to nothing here and the
	# program would degrade to ".[].field", which is not valid jq.
	field() { jq -r --arg v "$vmid" ".[\$v].$1 // \"?\"" "$INVENTORY"; }

	printf 'VM %s (%s)\n' "$vmid" "$(field description)"
	if [[ ! -r $conf ]]; then
		printf '  MISSING %s\n' "$conf"
		drift=$((drift + 1))
		continue
	fi

	# Proxmox omits keys that are unset, and awk still exits 0 when it finds
	# nothing, so an absent key arrives as an empty string rather than as a
	# failure. A command-substitution fallback therefore never fires, and every
	# default has to be applied explicitly.
	name=$(conf_get "$conf" name)
	[[ -n $name ]] || name="<unset>"
	check name "$(field name)" "$name"

	# Stored as "agent: enabled=1", and omitted entirely when the agent is off.
	# That omission is the whole failure this check exists to catch, so it is
	# reported as such rather than as a blank value.
	if [[ $(field guestAgent) == true ]]; then
		agent=$(conf_get "$conf" agent)
		[[ -n $agent ]] || agent="<unset>"
		check guest-agent "enabled=1" "$agent"
	fi

	net=$(conf_get "$conf" net0)
	bridge=$(net_field "$net" bridge)
	[[ -n $bridge ]] || bridge="<unset>"
	mac=$(net_field "$net" virtio)
	[[ -n $mac ]] || mac="<unset>"
	check bridge "$(field bridge)" "$bridge"
	check mac "$(field macAddress)" "$mac"

	memory=$(conf_get "$conf" memory)
	[[ -n $memory ]] || memory="<unset>"
	check memory "$(field memoryMiB)" "$memory"

	cores=$(conf_get "$conf" cores)
	[[ -n $cores ]] || cores="<unset>"
	check cores "$(field cores)" "$cores"

	# onboot is the one field with a meaningful default: Proxmox leaves the
	# line out entirely when the VM should not start at boot, which is exactly
	# what "0" means.
	live_onboot=$(conf_get "$conf" onboot)
	[[ -n $live_onboot ]] || live_onboot=0
	want_onboot=0
	if [[ $(field onboot) == true ]]; then
		want_onboot=1
	fi
	check onboot "$want_onboot" "$live_onboot"
done

printf '\n'
if ((drift == 0)); then
	printf 'no drift: %d field(s) across %d VM(s) match the declared inventory\n' \
		"$checked" "${#vmids[@]}"
	exit 0
fi
printf '%d field(s) differ between the declared inventory and the live configuration\n' \
	"$drift"
printf 'these VMs are managed by hand: reconcile the hypervisor or update the inventory\n'
exit 1
