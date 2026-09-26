# shellcheck shell=bash

# Control channel for the FLARE detonation guest.
#
# The Windows guest already runs the QEMU guest agent, so every operation here
# goes through virtio-serial rather than SSH, SMB or the VNC console. That
# matters for two reasons: the guest has no reachable login that this repo
# knows credentials for, and the channel survives the guest being pulled off
# the isolated segment mid-case.
#
# Everything is driven with `pvesh` rather than `qm agent`. The `qm` wrapper
# validates its subcommand against a hardcoded enumeration that predates
# guest-exec on this PVE build, so `qm agent <vmid> exec` is rejected as an
# unknown argument even though the API endpoint exists and works.

# Multi-argument exec has to be sent as repeated --command flags. A single
# comma-joined value is not split by pvesh and reaches the guest as one
# program name, which fails with ENOENT.
#
# PowerShell is passed as -EncodedCommand (base64 UTF-16LE) so arbitrary
# script text, quotes and backslashes in Windows paths survive the trip
# through three layers of argument marshalling untouched.
readonly POWERSHELL_PATH=${FLARE_AGENT_POWERSHELL:-C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe}

# file-write rejects a content string longer than 61440 characters. Base64
# inflates by 4/3, so 32768 raw bytes is the largest chunk that stays
# comfortably inside that ceiling.
readonly PUSH_CHUNK_BYTES=32768

# file-read accepts up to 16 MiB per call, but the response is carried as one
# base64 string through the virtio-serial transport. 1 MiB raw keeps each
# round trip small enough to stay responsive.
readonly PULL_CHUNK_BYTES=1048576

# The guest agent stops draining requests after a burst of file writes, and a
# chunk stranded by a cut off write cannot be removed even as SYSTEM until the
# agent is restarted. Recovering that by hand means reading a failed transfer
# and working out that the fix is a service restart, so the transport layer
# does it instead and retries the one operation that failed. Recovery is only
# ever wired into idempotent work: a re-sent chunk and a re-read file cannot
# change the outcome, whereas re-running a sample that merely timed out would
# detonate it twice. Never call this from a detonation path.
readonly QGA_RECOVERY_POLLS=${FLARE_AGENT_QGA_RECOVERY_POLLS:-20}
readonly QGA_RECOVERY_INTERVAL=${FLARE_AGENT_QGA_RECOVERY_INTERVAL:-3}

# guest-exec has no server-side timeout on this API version, so the wait for
# a pid to exit is bounded here instead. A detonation sample can legitimately
# run for a long time, hence the generous default. Override per invocation
# with --timeout, since a triage command and a detonation differ by orders of
# magnitude in how long they are allowed to take.
readonly DEFAULT_EXEC_TIMEOUT=${FLARE_AGENT_EXEC_TIMEOUT:-300}

# The agent channel is occasionally unavailable for a moment right after a
# large burst of file writes, which shows up as a failed launch rather than as
# a wrong answer. Retrying a launch is safe: nothing has been started yet.
readonly LAUNCH_ATTEMPTS=${FLARE_AGENT_LAUNCH_ATTEMPTS:-3}

# Guest-side tooling worth knowing about before a case starts. Absent entries
# are reported by `doctor` rather than treated as an error, because a triage
# case needs very little of this and a full detonation needs nearly all of it.
readonly -a FLARE_AGENT_GUEST_TOOLS=(
	ImDisk.exe
	ramdisk.exe
	aim_ll.exe
	Procmon.exe
	Procmon64.exe
	pe-sieve.exe
	pe-sieve64.exe
	PE-Sieve64.exe
	hollows_hunter.exe
	floss.exe
	x64dbg.exe
	pestudio.exe
)

# Where collected artifacts are staged on this host. Deliberately under /run:
# volatile analysis output should not accumulate on the host's persistent
# storage, and the case write-up is what gets exported, not the raw dumps.
readonly ARTIFACT_DIR=${FLARE_AGENT_ARTIFACT_DIR:-/run/flare-artifacts}

usage() {
	cat <<'EOF'
Control the FLARE detonation guest over the QEMU guest agent.

Usage:
  flare-agent [options] <command> <vmid> [arguments]

Commands:
  doctor <vmid>
      Preflight for starting a case: agent reachability, guest memory, which
      analysis tooling is present, whether a RAM disk backend is available,
      and where artifacts would be staged. Reports gaps, does not fix them.

  ping <vmid>
      Check that the guest agent answers.

  info <vmid>
      Print guest OS, hostname, addresses and free memory.

  exec <vmid> <program> [args...]
      Run a program in the guest. No shell is involved, so arguments are
      passed verbatim and need no quoting or escaping. Guest stdout is
      forwarded to stdout, guest stderr to stderr, and the guest's exit
      status becomes this command's exit status.

  powershell <vmid> <script>
      Run a PowerShell script in the guest. The script is delivered as
      -EncodedCommand, so it may contain quotes, backticks and Windows
      paths without any shell escaping. Guest CRLF line endings are
      normalised to LF.

  push <vmid> <local-file> <windows-path>
      Copy a local file to the guest, chunked to fit the agent's per-call
      content limit, then verified by comparing SHA-256 in both places.

  pull <vmid> <windows-path> [local-file]
      Copy a file out of the guest, read in ranges and base64-decoded so
      binary content survives intact. Defaults to the basename in the
      current directory.

  raw <vmid> <agent-command> [key=value ...]
      Escape hatch: call any guest-agent command directly, including ones
      this wrapper does not model. Each key=value pair is sent as --key value.

Options:
  --timeout <seconds>   How long to wait for a guest command. Default 300.
                        A detonation needs far longer than a triage command,
                        which is why this is per invocation.
  --node <name>         PVE node to talk to. Default: this host's hostname.
  -h, --help            Show this help.

Environment:
  FLARE_AGENT_NODE             Same as --node.
  FLARE_AGENT_EXEC_TIMEOUT     Default for --timeout.
  FLARE_AGENT_POWERSHELL       Full path to powershell.exe in the guest.
  FLARE_AGENT_ARTIFACT_DIR     Where artifacts are staged. Default
                               /run/flare-artifacts.
  FLARE_AGENT_LAUNCH_ATTEMPTS  Retries for a transient launch failure.
                               Default 3.

Examples:
  flare-agent doctor 200
  flare-agent ping 200
  flare-agent exec 200 C:\\Windows\\System32\\cmd.exe /c whoami
  flare-agent powershell 200 'Get-Process | Where-Object CPU | Select-Object -First 5'
  flare-agent push 200 ./sample.exe 'C:\Windows\Temp\sample.exe'
  flare-agent --timeout 1800 powershell 200 'Start-Sleep -Seconds 900'
  flare-agent pull 200 'C:\Windows\Temp\dump.dmp' ./dump.dmp
EOF
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

warn() {
	printf 'warning: %s\n' "$*" >&2
}

note() {
	printf '==> %s\n' "$*"
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# The API path is built from the node name, so a mismatch here silently
# targets the wrong (or a nonexistent) cluster member.
resolve_node() {
	if [[ -n ${FLARE_AGENT_NODE:-} ]]; then
		printf '%s' "$FLARE_AGENT_NODE"
		return 0
	fi
	local detected=""
	if [[ -r /proc/sys/kernel/hostname ]]; then
		detected=$(tr -d '\n' </proc/sys/kernel/hostname)
	fi
	[[ -n $detected ]] || detected=$(hostname 2>/dev/null || printf '')
	[[ -n $detected ]] || die "cannot determine the PVE node name; set FLARE_AGENT_NODE"
	printf '%s' "$detected"
}

# NODE is resolved in the entry point below, after the command line has been
# parsed, so that --node can override the auto-detected value.

api_path() {
	local vmid=$1
	printf '/nodes/%s/qemu/%s/agent' "$NODE" "$vmid"
}

# Some agent endpoints wrap their payload in a "result" object and some do
# not: get-osinfo answers {"result":{...}} while exec-status answers
# {"exitcode":..,"exited":..} flat. Verified against VM 200, but it is
# inconsistent enough to be worth stating, because reading .exitcode off a
# wrapped response would silently yield 0 and report a failing guest command
# as a success.

# Fail early and clearly rather than letting pvesh report a confusing
# "no such VM" once the guest agent call is already in flight.
require_running_vm() {
	local vmid=$1 status
	status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}') || status=""
	[[ -n $status ]] || die "VM $vmid does not exist on node $NODE"
	[[ $status == running ]] || die "VM $vmid is not running (status: $status)"
}

# Quote a Windows path as a PowerShell single-quoted string, where the only
# escape is a doubled quote.
ps_quote() {
	printf "'%s'" "${1//\'/\'\'}"
}

# Split a Windows path on either separator. POSIX dirname and basename treat
# a backslash as an ordinary character, so a path like C:\Windows\Temp would
# come back as a single unhelpfully named leaf.
win_dirname() {
	local path=$1
	if [[ $path == *\\* ]]; then
		printf '%s' "${path%\\*}"
	elif [[ $path == */* ]]; then
		printf '%s' "${path%/*}"
	else
		printf '.'
	fi
}

win_basename() {
	local path=$1
	if [[ $path == *\\* ]]; then
		printf '%s' "${path##*\\}"
	elif [[ $path == */* ]]; then
		printf '%s' "${path##*/}"
	else
		printf '%s' "$path"
	fi
}

# PowerShell to clear any part files left behind by an interrupted push.
# Written as a function so cmd_push stays readable and the escaping of
# PowerShell's own sigils is confined to one place.
remove_parts_script() {
	local remote_path=$1 part_prefix=$2
	cat <<EOF
\$ErrorActionPreference = 'SilentlyContinue'
Get-ChildItem -LiteralPath $(ps_quote "$(win_dirname "$remote_path")") -Force |
	Where-Object { \$_.Name.StartsWith($(ps_quote "$(win_basename "$part_prefix")")) } |
	Remove-Item -Force
EOF
}

# PowerShell to count the staged part files for a push, so that a cleanup can
# be confirmed rather than assumed. Remove-Item is silenced in the script
# above, which means a part still held open by an abandoned attempt makes the
# removal a silent no-op.
count_parts_script() {
	local remote_path=$1 part_prefix=$2
	cat <<EOF
\$ErrorActionPreference = 'SilentlyContinue'
@(Get-ChildItem -LiteralPath $(ps_quote "$(win_dirname "$remote_path")") -Force |
	Where-Object { \$_.Name.StartsWith($(ps_quote "$(win_basename "$part_prefix")")) }).Count
EOF
}

# Clear staged parts, returning non-zero only if parts positively survive. A
# part left over from an interrupted push is normally removable, but while the
# guest still holds one open the removal does nothing, and the retry then dies
# on "in use by another process" several chunks in -- which reads like a
# transfer fault rather than the stale state it actually is. A count that comes
# back empty means the parts could not be enumerated at all, which is the
# ordinary case for a first push into a directory that does not exist yet, and
# is not treated as a failure.
cleanup_parts() {
	local vmid=$1 remote_path=$2 part_prefix=$3
	exec_powershell "$vmid" "$(remove_parts_script "$remote_path" "$part_prefix")" >/dev/null 2>&1 ||
		true
	local remaining
	remaining=$(exec_powershell "$vmid" "$(count_parts_script "$remote_path" "$part_prefix")" |
		tr -d '\r\n[:space:]') || remaining=""
	# Parts surviving a removal mean the guest still holds a handle, and
	# restarting the agent is what releases it. Removal is idempotent, so it is
	# safe to recover here rather than handing the operator the diagnosis.
	if [[ -n $remaining && $remaining != 0 ]]; then
		qga_recover "$vmid" || true
		exec_powershell "$vmid" "$(remove_parts_script "$remote_path" "$part_prefix")" >/dev/null 2>&1 ||
			true
		remaining=$(exec_powershell "$vmid" "$(count_parts_script "$remote_path" "$part_prefix")" |
			tr -d '\r\n[:space:]') || remaining=""
	fi
	[[ -z $remaining || $remaining == 0 ]]
}

# Restart the guest's QEMU-GA and wait until it answers again. Returns non-zero
# if the agent never comes back, leaving the caller to report the original
# failure rather than a recovery failure.
#
# The restart is issued but deliberately never awaited: it tears down the very
# channel the request is travelling over, so its reply is normally lost. Only
# the follow-up ping decides whether the recovery worked.
qga_recover() {
	local vmid=$1
	note "guest agent in VM $vmid has stopped draining requests, restarting it"
	launch_exec_retry "$vmid" "$POWERSHELL_PATH" -NoProfile -NonInteractive \
		-OutputFormat Text -Command 'Restart-Service QEMU-GA -Force' >/dev/null 2>&1 || true
	local i
	for ((i = 0; i < QGA_RECOVERY_POLLS; i++)); do
		sleep "$QGA_RECOVERY_INTERVAL"
		if pvesh create "$(api_path "$vmid")/ping" --output-format json >/dev/null 2>&1; then
			note "guest agent in VM $vmid is responding again"
			return 0
		fi
	done
	return 1
}

# Write one chunk, recovering the agent and trying once more if it stalls.
#
# The retry is unconditional rather than matched against the error text: a
# wedged agent, a full disk and a rejected path all surface as a bare non-zero
# exit, and distinguishing them here would mean pattern matching prose that
# varies by API version. A restart cannot fix the latter two, so the cost of
# guessing wrong is one wasted service restart before the original error is
# reported unchanged.
write_chunk() {
	local vmid=$1 part_prefix=$2 index=$3 chunk=$4
	local part
	part=$(printf '%s%06d' "$part_prefix" "$index")
	pvesh create "$(api_path "$vmid")/file-write" \
		--file "$part" --content "$chunk" --encode 0 >/dev/null && return 0
	qga_recover "$vmid" || return 1
	pvesh create "$(api_path "$vmid")/file-write" \
		--file "$part" --content "$chunk" --encode 0 >/dev/null
}

# PowerShell to concatenate the numbered part files into the destination in
# lexicographic order, then clear them. FileStream.CopyTo keeps this binary
# safe, which byte-wise string concatenation would not.
join_parts_script() {
	local remote_path=$1 part_prefix=$2
	cat <<EOF
\$ErrorActionPreference = 'Stop'
\$target = $(ps_quote "$remote_path")
\$parts = @(Get-ChildItem -LiteralPath $(ps_quote "$(win_dirname "$remote_path")") -Force |
	Where-Object { \$_.Name.StartsWith($(ps_quote "$(win_basename "$part_prefix")")) } |
	Sort-Object -Property Name)
\$out = [IO.File]::Create(\$target)
try {
	foreach (\$part in \$parts) {
		\$in = [IO.File]::OpenRead(\$part.FullName)
		try { \$in.CopyTo(\$out) } finally { \$in.Dispose() }
	}
} finally { \$out.Dispose() }
\$parts | ForEach-Object { Remove-Item -LiteralPath \$_.FullName -Force }
EOF
}

# PowerShell to survey the guest in a single round trip. Probing one item per
# agent call would cost seconds each, and every call also pays process spawn
# and PowerShell startup, so a per-item preflight would dominate the time it is
# meant to save.
#
# The search deliberately skips C:\Windows: it is large, contains none of the
# tools being looked for, and is the one directory whose traversal reliably
# eats the time budget.
doctor_probe_script() {
	local list="" tool
	for tool in "${FLARE_AGENT_GUEST_TOOLS[@]}"; do
		[[ -z $list ]] || list+=","
		list+="'${tool}'"
	done
	cat <<EOF
\$ErrorActionPreference = 'SilentlyContinue'
\$wanted = @(${list})
\$wantedSet = @{}
foreach (\$n in \$wanted) { \$wantedSet[\$n.ToLower()] = \$n }
\$found = [ordered]@{}
function Find-Tools(\$items) {
	foreach (\$f in \$items) {
		\$key = \$f.Name.ToLower()
		if (\$wantedSet.ContainsKey(\$key) -and -not \$found.Contains(\$key)) { \$found[\$key] = \$f.FullName }
	}
}
foreach (\$dir in @('C:\\', 'C:\\Users\\thorn', 'C:\\Users\\thorn\\Downloads', 'C:\\Users\\Public')) {
	if (Test-Path -LiteralPath \$dir) { Find-Tools (Get-ChildItem -LiteralPath \$dir -File) }
}
foreach (\$dir in @('C:\\Tools', 'C:\\Flare', 'C:\\Program Files', 'C:\\Program Files (x86)', 'C:\\Users\\Public')) {
	if (Test-Path -LiteralPath \$dir) { Find-Tools (Get-ChildItem -LiteralPath \$dir -File -Recurse -Depth 2) }
}
\$os = Get-CimInstance Win32_OperatingSystem
\$drives = @(Get-CimInstance Win32_LogicalDisk | ForEach-Object {
	[ordered]@{ name = \$_.DeviceID; type = \$_.DriveType; sizeMiB = [int](\$_.Size / 1MB); freeMiB = [int](\$_.FreeSpace / 1MB) }
})
[ordered]@{
	freeMemMiB = [int](\$os.FreePhysicalMemory / 1KB)
	totalMemMiB = [int](\$os.TotalVisibleMemorySize / 1KB)
	found = \$found
	drives = \$drives
} | ConvertTo-Json -Depth 4 -Compress
EOF
}

# Emit a completed exec-status payload: stdout and stderr on their own
# streams, then the guest's exit status as ours.
emit_result() {
	local reply=$1
	local code truncated out err
	code=$(jq -r '.exitcode // 0' <<<"$reply")
	truncated=$(jq -r '."out-truncated" // 0' <<<"$reply")
	out=$(jq -j '."out-data" // ""' <<<"$reply")
	err=$(jq -j '."err-data" // ""' <<<"$reply")

	[[ $truncated == 0 ]] || warn "guest output was truncated by the agent"

	# The guest emits CRLF; a POSIX caller should not have to strip carriage
	# returns to compare output.
	[[ -z $out ]] || printf '%s' "$out" | tr -d '\r'
	[[ -z $err ]] || printf '%s' "$err" | tr -d '\r' >&2

	# Windows status codes are signed 32-bit and routinely fall outside the
	# 0-255 range a POSIX exit status can carry. Report the real value and
	# collapse to a generic failure rather than silently truncating it.
	if ((code < 0 || code > 255)); then
		warn "guest exit status $code does not fit a POSIX exit status; reporting 1"
		return 1
	fi
	return "$code"
}

# guest-exec is asynchronous on this API version: the create call returns a
# pid and the result has to be polled. There is no server-side timeout, so
# the loop is bounded locally.
#
# The two ways this can fail mean very different things to whoever is running a
# case, so they are reported distinctly. A command that is still running after
# the deadline is a slow sample; a pid the agent can no longer tell us about is
# a broken channel, and no amount of extra timeout will help. Collapsing both
# into "timed out" is what made an early transient stall look like a hang.
#
# Sets AWAIT_OUTCOME to ok, timeout or unreachable for the caller to report.
AWAIT_OUTCOME=""
AWAIT_POLLS=0
AWAIT_MISSES=0
await_result() {
	local vmid=$1 pid=$2 timeout=$3
	local deadline=$((SECONDS + timeout))
	local reply exited
	AWAIT_OUTCOME=timeout
	AWAIT_POLLS=0
	AWAIT_MISSES=0
	while ((SECONDS < deadline)); do
		reply=$(pvesh get "$(api_path "$vmid")/exec-status" --pid "$pid" --output-format json 2>/dev/null) || reply=""
		if [[ -n $reply ]]; then
			exited=$(jq -r '.exited // 0' <<<"$reply" 2>/dev/null) || exited=0
			if [[ $exited == 1 ]]; then
				AWAIT_OUTCOME=ok
				printf '%s' "$reply"
				return 0
			fi
			AWAIT_MISSES=0
			AWAIT_POLLS=$((AWAIT_POLLS + 1))
		else
			# The channel dropped. Tolerate brief gaps, but only for as long
			# as the pid has been answering us, so a genuinely wedged agent
			# still fails fast instead of burning the whole timeout.
			AWAIT_MISSES=$((AWAIT_MISSES + 1))
			AWAIT_POLLS=$((AWAIT_POLLS + 1))
			if ((AWAIT_POLLS >= 10 && AWAIT_MISSES >= 10)); then
				AWAIT_OUTCOME=unreachable
				return 1
			fi
		fi
		sleep 0.5
	done
	return 1
}

launch_exec() {
	local vmid=$1
	shift
	local -a command_args=()
	local argument
	for argument in "$@"; do
		command_args+=(--command "$argument")
	done
	pvesh create "$(api_path "$vmid")/exec" "${command_args[@]}" --output-format json
}

# A launch either produces a pid or it does not; nothing has run yet at the
# point of failure, so a transient channel error is worth retrying with a
# short backoff rather than aborting the whole operation.
launch_exec_retry() {
	local vmid=$1
	shift
	local attempt=0 reply=""
	while ((attempt < LAUNCH_ATTEMPTS)); do
		if reply=$(launch_exec "$vmid" "$@") &&
			[[ -n $(jq -r '.pid // empty' <<<"$reply" 2>/dev/null) ]]; then
			printf '%s' "$reply"
			return 0
		fi
		attempt=$((attempt + 1))
		((attempt < LAUNCH_ATTEMPTS)) && sleep $((attempt * 2))
	done
	printf '%s' "$reply"
	return 1
}

# Run an arbitrary argv in the guest and propagate its status.
exec_argv() {
	local vmid=$1
	shift
	(($# > 0)) || die "exec needs a program to run"
	require_running_vm "$vmid"

	local launch pid reply
	launch=$(launch_exec_retry "$vmid" "$@") ||
		die "could not start the command in VM $vmid after $LAUNCH_ATTEMPTS attempts"
	pid=$(jq -r '.pid // empty' <<<"$launch" 2>/dev/null) || pid=""
	[[ -n $pid && $pid != null ]] || die "the guest agent returned no pid for VM $vmid"

	if ! reply=$(await_result "$vmid" "$pid" "$EXEC_TIMEOUT"); then
		case $AWAIT_OUTCOME in
		unreachable)
			die "lost contact with the guest agent in VM $vmid after ${AWAIT_POLLS} polls (pid $pid); the command may still be running"
			;;
		*)
			die "command still running in VM $vmid after ${EXEC_TIMEOUT}s (pid $pid); raise --timeout if the sample needs longer"
			;;
		esac
	fi
	emit_result "$reply"
}

# Run a PowerShell script in the guest. Encoding to UTF-16LE base64 is what
# -EncodedCommand expects, and it removes every quoting hazard from the path
# between this script and the guest.
exec_powershell() {
	local vmid=$1 script=$2
	[[ -n $script ]] || die "powershell needs a script to run"
	local encoded
	# PowerShell abandons plain-text serialisation the moment its output is
	# not a console, which over the agent channel is always. Forcing Text
	# keeps guest stdout and stderr parseable by whatever consumes them
	# downstream, and silencing progress records drops the "Preparing modules
	# for first use" banner that otherwise precedes every single call.
	script="\$ProgressPreference = 'SilentlyContinue'; $script"
	encoded=$(printf '%s' "$script" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
	exec_argv "$vmid" "$POWERSHELL_PATH" \
		-NoProfile -NonInteractive -OutputFormat Text -EncodedCommand "$encoded"
}

cmd_ping() {
	local vmid=$1
	require_running_vm "$vmid"
	# guest-ping is a command rather than a query, so it has to be POSTed.
	# Asking for it with a GET fails with "no handler defined" even when the
	# agent is perfectly healthy.
	pvesh create "$(api_path "$vmid")/ping" --output-format json >/dev/null ||
		die "VM $vmid did not answer a guest agent ping"
	note "VM $vmid guest agent is responding"
}

cmd_info() {
	local vmid=$1
	require_running_vm "$vmid"
	note "VM $vmid guest agent is responding"
	printf '\n-- osinfo --\n'
	pvesh get "$(api_path "$vmid")/get-osinfo" --output-format json
	printf '\n-- hostname --\n'
	pvesh get "$(api_path "$vmid")/get-host-name" --output-format json
	printf '\n-- interfaces --\n'
	pvesh get "$(api_path "$vmid")/network-get-interfaces" --output-format json |
		jq -r '.[] | select(.["ip-addresses"] != null) |
      "  \(.name) \(.["hardware-address"] // "")\n" +
      (."ip-addresses" | map("    \(.["ip-address"])/\(.prefix)") | join("\n"))'
	printf '\n-- memory (MiB total / free) --\n'
	local total free
	read -r total free < <(
		exec_powershell "$vmid" \
			'(Get-CimInstance Win32_OperatingSystem |
          Select-Object TotalVisibleMemorySize, FreePhysicalMemory |
          ConvertTo-Json -Compress)' 2>/dev/null | tr -d '\r'
	)
	if [[ -n ${total:-} ]]; then
		printf '  %s / %s\n' "$((total / 1024))" "$((free / 1024))"
	fi
}

cmd_doctor() {
	local vmid=$1
	require_running_vm "$vmid"
	printf '== VM %s on node %s ==\n' "$vmid" "$NODE"

	local osinfo name version release hostname
	if ! osinfo=$(pvesh get "$(api_path "$vmid")/get-osinfo" --output-format json 2>/dev/null); then
		printf 'guest agent:  UNREACHABLE\n'
		return 1
	fi
	# get-osinfo wraps its payload and names the fields differently from what
	# the QEMU docs suggest; see the note next to api_path.
	name=$(jq -r '.result["pretty-name"] // .result.name // "?"' <<<"$osinfo")
	version=$(jq -r '.result["kernel-version"] // "?"' <<<"$osinfo")
	release=$(jq -r '.result["kernel-release"] // "?"' <<<"$osinfo")
	hostname=$(pvesh get "$(api_path "$vmid")/get-host-name" --output-format json 2>/dev/null |
		jq -r '.result["host-name"] // "?"' 2>/dev/null) || hostname="?"
	printf 'guest agent:  ok\n'
	printf 'os:           %s (NT %s.%s)\n' "$name" "$version" "$release"
	printf 'hostname:     %s\n' "$hostname"

	local probe
	if ! probe=$(exec_powershell "$vmid" "$(doctor_probe_script)" 2>/dev/null | tr -d '\r\n'); then
		printf 'guest survey: FAILED (agent answered osinfo but not a probe)\n'
		return 1
	fi
	[[ -n $probe ]] || probe='{}'

	printf 'memory:       %s MiB free of %s MiB\n' \
		"$(jq -r '.freeMemMiB // 0' <<<"$probe")" \
		"$(jq -r '.totalMemMiB // 0' <<<"$probe")"

	printf '\n-- guest tooling --\n'
	local tool
	for tool in "${FLARE_AGENT_GUEST_TOOLS[@]}"; do
		local hit
		hit=$(jq -r --arg t "${tool,,}" '.found[$t] // empty' <<<"$probe")
		if [[ -n $hit ]]; then
			printf '  ok      %-22s %s\n' "$tool" "$hit"
		else
			printf '  missing %s\n' "$tool"
		fi
	done

	# A RAM disk is the mechanism that keeps a sample off the guest's
	# persistent storage, so its absence is the difference between a lab that
	# can detonate and one that only appears to. Arsenal Image Mounter is
	# checked alongside ImDisk because its driver package is the one that still
	# imports cleanly on a current Windows 10 host; either CLI can back a
	# volatile disk, so either satisfies the requirement.
	local backend=""
	backend=$(jq -r '.found["imdisk.exe"] // .found["ramdisk.exe"] // .found["aim_ll.exe"] // empty' <<<"$probe")
	printf '\n-- verdict --\n'
	if [[ -n $backend ]]; then
		printf '  RAM disk:     available (%s)\n' "$backend"
	else
		printf '  RAM disk:     UNAVAILABLE - no ImDisk, ramdisk or Arsenal in the guest\n'
		printf '                detonating now would write the sample to the qcow2.\n'
	fi

	printf '\n-- guest filesystems --\n'
	jq -r '.drives[] | "  \(.name)  \(.sizeMiB) MiB total, \(.freeMiB) MiB free (type \(.type))"' \
		<<<"$probe" 2>/dev/null || printf '  (none reported)\n'

	printf '\n-- this host --\n'
	if mkdir -p "$ARTIFACT_DIR" 2>/dev/null; then
		printf '  artifact dir: %s (%s MiB free)\n' "$ARTIFACT_DIR" \
			"$(df -Pm "$ARTIFACT_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
	else
		printf '  artifact dir: %s NOT WRITABLE\n' "$ARTIFACT_DIR"
	fi
	printf '  note:         /run is volatile; exported case reports, not raw dumps,\n'
	printf '                are what should survive a reboot.\n'
}

cmd_push() {
	local vmid=$1 local_path=$2 remote_path=$3
	[[ -f $local_path ]] || die "no such local file: $local_path"
	[[ -n $remote_path ]] || die "push needs a destination path in the guest"
	require_running_vm "$vmid"

	local size expected
	size=$(wc -c <"$local_path")
	expected=$(sha256sum "$local_path" | cut -d' ' -f1)
	note "pushing $(basename "$local_path") ($size bytes) to $remote_path in VM $vmid"

	# file-write always creates or replaces, so a chunk cannot be appended in
	# place. Each chunk therefore lands in its own numbered part file and a
	# single pass concatenates them in order afterwards. Writing the parts
	# under distinct names also means the destination path is only ever
	# created by the final step, so an interrupted push can never leave a
	# half-delivered sample sitting where the runbook expects a whole one.
	#
	# Indexes are zero-padded so that a plain lexicographic sort in the guest
	# reproduces the original byte order.
	local part_prefix="${remote_path}.thornixpart."
	local index=0 chunk chunks
	chunks=$(((size + PUSH_CHUNK_BYTES - 1) / PUSH_CHUNK_BYTES))
	((chunks > 0)) || chunks=1

	# Drop leftovers from an earlier failed attempt first, or they would be
	# concatenated into this push and silently corrupt it. Confirm the removal
	# actually took effect rather than trusting it, because a part the guest
	# still holds open survives a silenced Remove-Item without complaint.
	cleanup_parts "$vmid" "$remote_path" "$part_prefix" ||
		die "cannot clear staged chunks for $remote_path in VM $vmid; the guest agent still holds them open, so restart its QEMU-GA service and retry"

	while ((index < chunks)); do
		chunk=$(dd if="$local_path" bs="$PUSH_CHUNK_BYTES" skip="$index" count=1 2>/dev/null | base64 -w0)
		if ! write_chunk "$vmid" "$part_prefix" "$index" "$chunk"; then
			# Clear the parts written so far. Leaving them behind is what makes
			# the next attempt fail for reasons that have nothing to do with it.
			cleanup_parts "$vmid" "$remote_path" "$part_prefix" || true
			die "write chunk $index failed for $remote_path in VM $vmid"
		fi
		index=$((index + 1))
		if ((chunks > 1)); then
			printf '\r    chunk %d/%d' "$index" "$chunks" >&2
			((index == chunks)) && printf '\n' >&2
		fi
	done

	# The concatenation pass also creates the destination, so a zero-byte
	# push needs no special case here: it simply produces no parts and an
	# empty result.
	exec_powershell "$vmid" "$(join_parts_script "$remote_path" "$part_prefix")" >/dev/null ||
		die "could not assemble the staged chunks into $remote_path"

	# Compare digests rather than trusting the byte count: a silently mangled
	# sample is the one failure mode that would poison an entire case.
	local actual
	actual=$(exec_powershell "$vmid" \
		"(Get-FileHash -LiteralPath $(ps_quote "$remote_path") -Algorithm SHA256).Hash" |
		tr -d '\r\n[:space:]') || actual=""
	if [[ -z $actual ]]; then
		die "could not read back the digest of $remote_path in VM $vmid"
	fi
	if [[ ${actual,,} != "${expected,,}" ]]; then
		die "digest mismatch for $remote_path: sent $expected, guest has $actual"
	fi
	note "verified sha256 ${expected}"
}

cmd_pull() {
	local vmid=$1 remote_path=$2 local_path=${3:-}
	[[ -n $remote_path ]] || die "pull needs a source path in the guest"
	if [[ -z $local_path ]]; then
		local_path=$(win_basename "$remote_path")
	fi
	require_running_vm "$vmid"

	# The agent reports no total size, so ask the guest for the length and
	# drive the range loop from that.
	local size
	size=$(exec_powershell "$vmid" \
		"(Get-Item -LiteralPath $(ps_quote "$remote_path")).Length" | tr -d '\r\n[:space:]') || size=""
	[[ $size =~ ^[0-9]+$ ]] || die "could not determine the size of $remote_path in VM $vmid"
	note "pulling $remote_path ($size bytes) from VM $vmid to $local_path"

	: >"$local_path" || die "cannot write $local_path"
	if ((size == 0)); then
		note "guest file is empty"
		return 0
	fi

	local offset=0 content
	while ((offset < size)); do
		# --decode 0 hands back base64 instead of a JSON string of raw bytes,
		# which is what keeps binary content intact through JSON escaping.
		# jq -j suppresses the trailing newline that would corrupt the last byte.
		content=$(pvesh get "$(api_path "$vmid")/file-read" \
			--file "$remote_path" --offset "$offset" --count "$PULL_CHUNK_BYTES" \
			--decode 0 --output-format json |
			jq -j '.content // ""') || content=""
		[[ -n $content ]] || die "read of $remote_path failed at offset $offset"
		printf '%s' "$content" | base64 -d >>"$local_path" ||
			die "could not decode the chunk read at offset $offset"
		offset=$((offset + PULL_CHUNK_BYTES))
	done

	local expected actual
	actual=$(sha256sum "$local_path" | cut -d' ' -f1)
	expected=$(exec_powershell "$vmid" \
		"(Get-FileHash -LiteralPath $(ps_quote "$remote_path") -Algorithm SHA256).Hash" |
		tr -d '\r\n[:space:]') || expected=""
	if [[ -n $expected && ${expected,,} != "${actual,,}" ]]; then
		die "digest mismatch for $remote_path: guest has $expected, pulled $actual"
	fi
	note "verified sha256 ${actual}"
}

# Escape hatch for guest-agent commands this wrapper does not model.
cmd_raw() {
	local vmid=$1 agent_command=$2
	shift 2
	[[ -n $agent_command ]] || die "raw needs an agent command"
	local -a extra_args=()
	local pair key value
	for pair in "$@"; do
		[[ $pair == *=* ]] || die "raw arguments must be key=value, got: $pair"
		key=${pair%%=*}
		value=${pair#*=}
		extra_args+=("--$key" "$value")
	done
	# The agent splits its surface into queries (GET) and commands (POST), and
	# which one applies is not obvious from the command name alone. Try the
	# query form and fall back to the command form, so this stays a genuine
	# escape hatch rather than only reaching half the agent API.
	if pvesh get "$(api_path "$vmid")/$agent_command" \
		${extra_args+"${extra_args[@]}"} --output-format json; then
		return 0
	fi
	pvesh create "$(api_path "$vmid")/$agent_command" \
		${extra_args+"${extra_args[@]}"} --output-format json
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
	usage
	exit 0
fi

# Options are parsed before the subcommand so that the positional form stays
# exactly as it was. Everything after the subcommand belongs to the guest
# command and must not be interpreted here.
EXEC_TIMEOUT=$DEFAULT_EXEC_TIMEOUT
while (($# > 0)); do
	case $1 in
	--timeout)
		shift
		(($# > 0)) || die "--timeout needs a value"
		EXEC_TIMEOUT=$1
		;;
	--timeout=*)
		EXEC_TIMEOUT=${1#*=}
		;;
	--node)
		shift
		(($# > 0)) || die "--node needs a value"
		FLARE_AGENT_NODE=$1
		;;
	--node=*)
		FLARE_AGENT_NODE=${1#*=}
		;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		die "unknown option: $1 (options must come before the command)"
		;;
	*)
		break
		;;
	esac
	shift
done

[[ $EXEC_TIMEOUT =~ ^[0-9]+$ ]] || die "--timeout must be a whole number of seconds, got: $EXEC_TIMEOUT"
((EXEC_TIMEOUT > 0)) || die "--timeout must be greater than zero"

# Assigned then frozen separately: masking the exit status of resolve_node
# would hide its die on an undetectable node name.
NODE=$(resolve_node)
readonly NODE

[[ $# -ge 2 ]] || {
	usage >&2
	exit 2
}

readonly SUBCOMMAND=$1
readonly VMID=$2

require_command pvesh
require_command qm
require_command jq
require_command iconv
require_command base64
require_command sha256sum
require_command dd

case $SUBCOMMAND in
doctor) cmd_doctor "$VMID" ;;
ping) cmd_ping "$VMID" ;;
info) cmd_info "$VMID" ;;
exec)
	shift 2
	exec_argv "$VMID" "$@"
	;;
powershell)
	shift 2
	[[ $# -ge 1 ]] || die "powershell needs a script to run"
	exec_powershell "$VMID" "$*"
	;;
push)
	shift 2
	[[ $# -eq 2 ]] || die "push needs exactly: <vmid> <local-file> <windows-path>"
	cmd_push "$VMID" "$1" "$2"
	;;
pull)
	shift 2
	[[ $# -ge 1 && $# -le 2 ]] || die "pull needs: <vmid> <windows-path> [local-file]"
	cmd_pull "$VMID" "$1" "${2:-}"
	;;
raw)
	shift 2
	[[ $# -ge 1 ]] || die "raw needs an agent command"
	cmd_raw "$VMID" "$@"
	;;
*)
	usage >&2
	die "unknown command: $SUBCOMMAND"
	;;
esac
