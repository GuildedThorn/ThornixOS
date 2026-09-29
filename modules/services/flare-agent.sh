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
# round trip small enough to stay responsive. On memory-backed RAM disks the
# guest agent wedges on large reads; 256 KiB is a safer default.
# Adaptive: 64 KiB for small files (<1 MB), 256 KiB default, 1 MiB for large (>10 MB).
readonly PULL_CHUNK_BYTES_MIN=65536
readonly PULL_CHUNK_BYTES_DEFAULT=262144
readonly PULL_CHUNK_BYTES_MAX=1048576

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

  detonate <vmid> <local-sample> [run-args...]
      Run a sample on a RAM disk and collect the evidence, as one sequence:
      attach a memory-backed disk, refuse to continue unless Arsenal
      confirms the backing is memory, stage the sample onto it, run it,
      sweep the host state into an archive, pull the archive, then detach
      and verify the sample left nothing behind. Any failure detaches the
      disk and reports where the sample digest is, since a timed out run
      is not retried: a sample that only looks stuck would be run twice.

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

# --- detonation: RAM disk lifecycle -----------------------------------------
#
# The property worth protecting is that a sample exists only in guest memory.
# Arsenal can attach a disk backed by an image file on C:, which would put the
# sample straight onto the qcow2, so the backend is always requested as "vm" and
# then verified through Arsenal's own inventory rather than assumed.

readonly FLARE_AIM=${FLARE_AGENT_AIM:-C:\\Tools\\arsenal\\aim_ll.exe}
# Room for the sample plus what it unpacks, the collection staging and the
# archive. Overrunning this is how a disk runs out mid-detonation and Windows
# starts paging the sample to the qcow2 instead.
readonly DETONATE_HEADROOM_MIB=${FLARE_AGENT_DETONATE_HEADROOM_MIB:-512}
readonly DETONATE_MIN_MIB=${FLARE_AGENT_DETONATE_MIN_MIB:-512}
# Ceiling, and the reason the guest's free memory is checked before attaching.
readonly DETONATE_MAX_MIB=${FLARE_AGENT_DETONATE_MAX_MIB:-2048}

# A drive letter nothing is using. R: is preferred so a lab reads the same way
# every time, falling through only when something already holds it.
ramdisk_free_letter_script() {
	cat <<'EOF'
$used = @((Get-CimInstance Win32_LogicalDisk).DeviceID)
foreach ($c in 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y') {
	$id = $c + ':'
	if ($used -notcontains $id) { Write-Output $id; break }
}
EOF
}

ramdisk_attach_script() {
	local letter=$1 size_mib=$2
	cat <<EOF
\$ErrorActionPreference = 'Continue'
& $(ps_quote "$FLARE_AIM") -a -t vm -s "${size_mib}M" -m $(ps_quote "$letter")
Write-Output ("AIM_EXIT=" + \$LASTEXITCODE)
EOF
}

# Arsenal's -l output is the authority on what backs a disk, and it is the only
# signal that distinguishes memory from an image file. A vm disk reports
# "Virtual Memory" with no "Image file:" line; a file-backed one reports the
# image path instead. Win32_LogicalDisk is no help here -- these volumes report
# DriveType 3, indistinguishable from the system disk, and report a size of 0
# until they are formatted.
ramdisk_gate_script() {
	local letter=$1
	cat <<EOF
\$ErrorActionPreference = 'SilentlyContinue'
\$out = (& $(ps_quote "$FLARE_AIM") -l 2>&1 | Out-String)
\$blocks = \$out -split '(?:\r?\n){2,}'
\$want = 'Mounted at $(printf '%s' "$letter" | tr '[:upper:]' '[:lower:]')\'
foreach (\$b in \$blocks) {
	if (\$b -notmatch [regex]::Escape(\$want)) { continue }
	if (\$b -match 'Image file:') {
		Write-Output 'GATE=IMAGE_BACKED'
	} elseif (\$b -match 'Virtual Memory') {
		\$size = if (\$b -match 'Size: (\d+) bytes') { \$Matches[1] } else { '?' }
		Write-Output ("GATE=VM size=" + \$size)
	} else {
		Write-Output 'GATE=UNKNOWN_BACKING'
	}
	break
}
if (\$out -notmatch [regex]::Escape(\$want)) { Write-Output 'GATE=NOT_MOUNTED' }
EOF
}

ramdisk_format_script() {
	local letter=$1
	local drive=${letter%:}
	cat <<EOF
\$ErrorActionPreference = 'Continue'
\$part = Get-Partition -DriveLetter $(ps_quote "$drive")
if (-not \$part) { Write-Output 'FORMAT=NO_PARTITION'; exit }
\$part | Get-Volume | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'RAMLAB' -Force -Confirm:\$false | Out-Null
\$v = \$part | Get-Volume
Write-Output ("FORMAT=" + \$v.FileSystem + " free=" + [int](\$v.SizeRemaining / 1MB) + "MiB")
EOF
}

# Run the sample and capture what it did. stdout, stderr and the exit code land
# on the RAM disk alongside everything else, so the evidence of the run is
# collected by the same sweep as the host state.
detonate_run_script() {
	local letter=$1 exe=$2 argline=$3 outdir=$4
	# An empty argument list must stay empty rather than becoming a single empty
	# argument, which some samples read as a filename.
	local argl='@()'
	[[ -n $argline ]] && argl="@($(ps_quote "$argline"))"
	cat <<EOF
\$ErrorActionPreference = 'Continue'
\$stdout = $(ps_quote "$outdir\\run-stdout.txt")
\$stderr = $(ps_quote "$outdir\\run-stderr.txt")
\$exitf = $(ps_quote "$outdir\\run-exit.txt")
\$argl = $argl
try {
	\$p = Start-Process -FilePath $(ps_quote "$exe") -ArgumentList \$argl -WorkingDirectory $(ps_quote "$outdir") -RedirectStandardOutput \$stdout -RedirectStandardError \$stderr -PassThru -Wait -NoNewWindow
	Set-Content -LiteralPath \$exitf -Value \$p.ExitCode
	Write-Output ("RUN_EXIT=" + \$p.ExitCode)
} catch {
	# A sample that cannot be started at all is still a result worth keeping.
	Set-Content -LiteralPath \$exitf -Value 'launch-failed'
	Set-Content -LiteralPath \$stderr -Value \$_.Exception.Message
	Write-Output 'RUN_EXIT=LAUNCH_FAILED'
}
EOF
}

# Sweep the host state that a detonation is judged against. Everything is
# written to the RAM disk, including the archive, so the collection itself
# leaves no trace on the qcow2 either. Each item is attempted independently: a
# locked hive or a log that will not export must not cost us the rest.
detonate_collect_script() {
	local letter=$1 sample_hash=$2
	cat <<EOF
\$ErrorActionPreference = 'SilentlyContinue'
\$stage = $(ps_quote "$letter")
\$dir = Join-Path \$stage 'artifacts'
New-Item -ItemType Directory -Path \$dir -Force | Out-Null
\$log = New-Object System.Collections.Generic.List[string]
\$log.Add("sample_sha256=$sample_hash")
\$log.Add("collected=\$(Get-Date -Format o)")

function Grab(\$src, \$name) {
	if (-not (Test-Path -LiteralPath \$src)) { \$log.Add("miss  \$name"); return }
	try {
		Copy-Item -LiteralPath \$src -Destination (Join-Path \$dir \$name) -Force -ErrorAction Stop
		\$log.Add("ok    \$name")
	} catch { \$log.Add("LOCKED \$name") }
}

# Registry hives: what ran, what was configured to run, which accounts exist.
foreach (\$h in 'SAM', 'SYSTEM', 'SOFTWARE', 'SECURITY', 'DEFAULT') {
	Grab "C:\\Windows\\System32\\config\\\$h" "hive-\$h.hive"
}
Grab 'C:\Windows\AppCompat\Programs\Amcache.hve' 'Amcache.hve'
Grab 'C:\Windows\SRU\SRUMDATA.dat' 'SRUMDATA.dat'
Get-ChildItem 'C:\Windows\Prefetch\*.pf' -Force | ForEach-Object { Grab \$_.FullName "prefetch-\$(\$_.Name)" }

# Event logs exported natively so timestamps and channels survive intact.
foreach (\$log_name in 'Security', 'System', 'Application', 'Microsoft-Windows-PowerShell/Operational', 'Microsoft-Windows-Sysmon/Operational') {
	\$dest = Join-Path \$dir ("evtx-" + (\$log_name -replace '[^A-Za-z]', '_') + ".evtx")
	if (Test-Path "C:\\Windows\\System32\\winevt\\Logs\\\$(\$log_name -replace '/', '\\\\').evtx") {
		& wevtutil epl \$log_name \$dest /ow:true /q:true 2>\$null | Out-Null
		\$log.Add("\$(if (Test-Path \$dest) { 'ok    ' } else { 'miss  ' })evtx-\$log_name")
	} else { \$log.Add("miss  evtx-\$log_name") }
}

# Live network and host state, as text, taken after the run.
ipconfig /all 2>\$null | Out-File (Join-Path \$dir 'net-ipconfig.txt') -Encoding utf8
ipconfig /displaydns 2>\$null | Out-File (Join-Path \$dir 'net-dnscache.txt') -Encoding utf8
route print 2>\$null | Out-File (Join-Path \$dir 'net-route.txt') -Encoding utf8
netstat -ano 2>\$null | Out-File (Join-Path \$dir 'net-netstat.txt') -Encoding utf8
arp -a 2>\$null | Out-File (Join-Path \$dir 'net-arp.txt') -Encoding utf8
tasklist /svc 2>\$null | Out-File (Join-Path \$dir 'proc-tasklist.txt') -Encoding utf8
Get-Process 2>\$null | Select-Object Id, ProcessName, Path, StartTime |
	Out-File (Join-Path \$dir 'proc-list.txt') -Encoding utf8
Get-Service 2>\$null | Select-Object Name, Status, StartType |
	Out-File (Join-Path \$dir 'svc-list.txt') -Encoding utf8
Get-CimInstance Win32_StartupCommand 2>\$null |
	Out-File (Join-Path \$dir 'autoruns.txt') -Encoding utf8

# Memory dump of LSASS using built-in comsvcs.dll (no external tools).
# Dumps the LSASS process which often contains credentials, crypto keys, etc.
\$lsass_pid = (Get-Process -Name lsass -ErrorAction SilentlyContinue).Id
if (\$lsass_pid) {
	\$dump = Join-Path \$dir 'lsass.dmp'
	rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump \$lsass_pid \$dump full 2>\$null | Out-Null
	\$log.Add("\$(if (Test-Path \$dump) { 'ok    ' } else { 'miss  ' })lsass.dmp")
} else {
	\$log.Add("miss  lsass.dmp")
}

\$log | Out-File (Join-Path \$dir 'manifest.txt') -Encoding utf8
# The archive is built on the RAM disk and pulled from there, so the host never
# sees the unpacked evidence at all.
\$zip = Join-Path \$stage 'artifacts.zip'
Remove-Item \$zip -Force -ErrorAction SilentlyContinue
try {
	Compress-Archive -Path (Join-Path \$dir '*') -DestinationPath \$zip -Force -ErrorAction Stop
	Write-Output ("ZIP=" + [int]((Get-Item \$zip).Length / 1KB) + "KiB")
} catch { Write-Output 'ZIP=FAILED' }
EOF
}

ramdisk_detach_script() {
	local letter=$1 flag=${2:-d}
	cat <<EOF
\$ErrorActionPreference = 'Continue'
& $(ps_quote "$FLARE_AIM") -$flag -m $(ps_quote "$letter") 2>&1 | Out-Null
Start-Sleep -Seconds 2
Write-Output ("DETACH_EXIT=" + \$LASTEXITCODE)
EOF
}

# Deliberately cheap, because it runs on every detach attempt; the recursive
# sweep below is slow enough that repeating it per attempt would dominate.
ramdisk_letter_gone_script() {
	local letter=$1
	cat <<EOF
\$ErrorActionPreference = 'SilentlyContinue'
\$drive = '$(printf '%s' "${letter%:}" | tr '[:upper:]' '[:lower:]')'
Write-Output ("LETTER_GONE=" + \$(if (Test-Path (\$drive + ':\')) { 0 } else { 1 }))
EOF
}

# Does the sample's filename appear anywhere on persistent storage? A run that
# reported success while leaving a copy behind is the failure this whole
# mechanism exists to prevent, so it is checked rather than assumed.
ramdisk_stray_script() {
	local name=$1
	cat <<EOF
\$ErrorActionPreference = 'SilentlyContinue'
\$stray = 0
foreach (\$root in 'C:\Users', 'C:\ProgramData', 'C:\Windows\Temp', 'C:\PerfLogs') {
	if (Test-Path \$root) {
		\$stray += @(Get-ChildItem -LiteralPath \$root -Recurse -Force -Filter $(ps_quote "$name") -ErrorAction SilentlyContinue).Count
	}
}
Write-Output ("STRAY_COPIES=" + \$stray)
EOF
}

# The whole sequence, because the safety property is in the order: attach,
# verify the backing is memory, stage, run, collect, detach. Each step is
# useless alone -- a RAM disk with no detach is worse than none, and a sample
# staged without a memory-backed disk behind it is the qcow2 all over again.

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
	local join_script
	join_script=$(
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
} finally {
	\$out.Dispose()
}
EOF
	)
	exec_powershell "$vmid" "$join_script" >/dev/null ||
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

	# Adaptive chunk size: 64 KiB for small files, 256 KiB default, 1 MiB for large
	local chunk_bytes
	if ((size < 1048576)); then
		chunk_bytes=$PULL_CHUNK_BYTES_MIN
	elif ((size > 10485760)); then
		chunk_bytes=$PULL_CHUNK_BYTES_MAX
	else
		chunk_bytes=$PULL_CHUNK_BYTES_DEFAULT
	fi
	note "pulling $remote_path ($size bytes, chunk=${chunk_bytes}B) from VM $vmid to $local_path"

	: >"$local_path" || die "cannot write $local_path"
	if ((size == 0)); then
		note "guest file is empty"
		return 0
	fi

	local offset=0 content
	local pull_retries=0
	local max_pull_retries=3
	while ((offset < size)); do
		# --decode 0 hands back base64 instead of a JSON string of raw bytes,
		# which is what keeps binary content intact through JSON escaping.
		# jq -j suppresses the trailing newline that would corrupt the last byte.
		# A read is idempotent, so a wedged agent is recovered from and the same
		# range re-read: the offset has not moved, so a duplicate cannot corrupt
		# the output.
		pull_retries=0
		while ((pull_retries <= max_pull_retries)); do
			if ! content=$(pvesh get "$(api_path "$vmid")/file-read" \
				--file "$remote_path" --offset "$offset" --count "$chunk_bytes" \
				--decode 0 --output-format json |
				jq -j '.content // ""'); then
				content=""
			fi
			if [[ -n $content ]]; then
				break
			fi
			((pull_retries++))
			if ((pull_retries <= max_pull_retries)); then
				note "pull chunk at offset $offset failed (attempt $pull_retries/$max_pull_retries), recovering guest agent"
				qga_recover "$vmid" || true
				sleep 2
			fi
		done
		[[ -n $content ]] || die "read of $remote_path failed at offset $offset after $max_pull_retries retries"
		printf '%s' "$content" | base64 -d >>"$local_path" ||
			die "could not decode the chunk read at offset $offset"
		offset=$((offset + chunk_bytes))
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

# =============================================================================
# SSH Transport Layer
# =============================================================================
# An alternative transport that uses SSH instead of QEMU guest agent. This is
# useful when the guest agent channel is unreliable or when the VM is not on
# the same Proxmox cluster. Requires OpenSSH server on the Windows guest and
# key-based authentication configured.
#
# SSH transport is enabled by setting:
#   FLARE_SSH_HOST=<IP or hostname of the Windows guest>
#   FLARE_SSH_USER=<username> (default: thorn)
#   FLARE_SSH_KEY=<path to private key> (optional, uses ssh-agent if unset)
#   FLARE_SSH_PORT=<port> (default: 22)
#
# When FLARE_SSH_HOST is set, all commands route through SSH instead of QGA.

# SSH configuration
FLARE_SSH_HOST=${FLARE_SSH_HOST:-}
FLARE_SSH_USER=${FLARE_SSH_USER:-thorn}
FLARE_SSH_KEY=${FLARE_SSH_KEY:-}
FLARE_SSH_PORT=${FLARE_SSH_PORT:-22}
# Array of SSH options to avoid word-splitting issues
FLARE_SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes)

# Check if SSH transport is enabled
ssh_transport_enabled() {
	[[ -n ${FLARE_SSH_HOST:-} ]]
}

# Build SSH command array
ssh_cmd() {
	local -a cmd=(ssh "${FLARE_SSH_OPTS[@]}" -p "${FLARE_SSH_PORT}")
	[[ -n ${FLARE_SSH_KEY:-} ]] && cmd+=(-i "${FLARE_SSH_KEY}")
	cmd+=("${FLARE_SSH_USER}@${FLARE_SSH_HOST}")
	printf '%s\n' "${cmd[@]}"
}

# Run a command via SSH and return stdout/stderr/exit code
ssh_exec() {
	local -a ssh_args
	mapfile -t ssh_args < <(ssh_cmd)
	"${ssh_args[@]}" "$@"
}

# Run a PowerShell script via SSH (encoded as UTF-16LE base64 for -EncodedCommand)
ssh_exec_powershell() {
	local script=$1
	[[ -n $script ]] || die "ssh_exec_powershell needs a script to run"
	local encoded
	script="\$ProgressPreference = 'SilentlyContinue'; $script"
	encoded=$(printf '%s' "$script" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
	ssh_exec powershell.exe -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand "$encoded"
}

# Run an arbitrary command via SSH (no shell)
ssh_exec_argv() {
	ssh_exec "$@"
}

# Upload a file via SCP
ssh_push() {
	local local_path=$1 remote_path=$2
	[[ -f $local_path ]] || die "no such local file: $local_path"
	[[ -n $remote_path ]] || die "ssh_push needs a destination path"

	local -a scp_cmd=(scp "${FLARE_SSH_OPTS[@]}" -P "${FLARE_SSH_PORT}")
	[[ -n ${FLARE_SSH_KEY:-} ]] && scp_cmd+=(-i "${FLARE_SSH_KEY}")
	scp_cmd+=("$local_path" "${FLARE_SSH_USER}@${FLARE_SSH_HOST}:${remote_path}")
	"${scp_cmd[@]}"
}

# Download a file via SCP
ssh_pull() {
	local remote_path=$1 local_path=${2:-}
	[[ -n $remote_path ]] || die "ssh_pull needs a source path"
	[[ -z $local_path ]] && local_path=$(win_basename "$remote_path")

	local -a scp_cmd=(scp "${FLARE_SSH_OPTS[@]}" -P "${FLARE_SSH_PORT}")
	[[ -n ${FLARE_SSH_KEY:-} ]] && scp_cmd+=(-i "${FLARE_SSH_KEY}")
	scp_cmd+=("${FLARE_SSH_USER}@${FLARE_SSH_HOST}:${remote_path}" "$local_path")
	"${scp_cmd[@]}"
}

# Restart QEMU-GA service via SSH (replaces qga_recover)
ssh_qga_recover() {
	note "guest agent in VM (SSH) has stopped draining requests, restarting it"
	ssh_exec_powershell 'Restart-Service QEMU-GA -Force' >/dev/null 2>&1 || true
	local i
	for ((i = 0; i < QGA_RECOVERY_POLLS; i++)); do
		sleep "$QGA_RECOVERY_INTERVAL"
		if ssh_exec_powershell 'Write-Output "ok"' >/dev/null 2>&1; then
			note "guest agent in VM (SSH) is responding again"
			return 0
		fi
	done
	return 1
}

# Ping via SSH
ssh_ping() {
	if ssh_exec_powershell 'Write-Output "ok"' >/dev/null 2>&1; then
		note "VM (SSH) guest agent is responding"
		return 0
	fi
	die "VM (SSH) did not answer a guest agent ping"
}

# Get OS info via SSH
ssh_info() {
	note "VM (SSH) guest agent is responding"
	printf '\n-- osinfo --\n'
	ssh_exec_powershell '(Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber | ConvertTo-Json -Compress)'

	printf '\n-- hostname --\n'
	ssh_exec_powershell 'Write-Output $env:COMPUTERNAME'

	printf '\n-- interfaces --\n'
	ssh_exec_powershell 'Get-NetIPAddress | Where-Object {$_.AddressFamily -eq "IPv4" -and $_.InterfaceAlias -notlike "*Loopback*"} | Select-Object IPAddress, InterfaceAlias, PrefixOrigin | ConvertTo-Json -Compress'

	printf '\n-- memory (MiB total / free) --\n'
	local mem
	mem=$(ssh_exec_powershell '(Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory | ConvertTo-Json -Compress)' 2>/dev/null | tr -d '\r')
	if [[ -n ${mem:-} ]]; then
		local total free
		total=$(jq -r '.TotalVisibleMemorySize // 0' <<<"$mem")
		free=$(jq -r '.FreePhysicalMemory // 0' <<<"$mem")
		if [[ -n ${total:-} ]]; then
			printf '  %s / %s\n' "$((total / 1024))" "$((free / 1024))"
		fi
	fi
}

# Doctor via SSH
ssh_doctor() {
	printf '== VM (SSH) on %s ==\n' "${FLARE_SSH_HOST}"

	local osinfo
	if ! osinfo=$(ssh_exec_powershell '(Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber | ConvertTo-Json -Compress)' 2>/dev/null | tr -d '\r'); then
		printf 'guest agent:  UNREACHABLE\n'
		return 1
	fi
	local name version build hostname
	name=$(jq -r '.Caption // "?"' <<<"$osinfo")
	version=$(jq -r '.Version // "?"' <<<"$osinfo")
	build=$(jq -r '.BuildNumber // "?"' <<<"$osinfo")
	hostname=$(ssh_exec_powershell 'Write-Output $env:COMPUTERNAME' 2>/dev/null | tr -d '\r') || hostname="?"
	printf 'guest agent:  ok\n'
	printf 'os:           %s (NT %s.%s)\n' "$name" "$version" "$build"
	printf 'hostname:     %s\n' "$hostname"

	# Probe for tools
	local probe
	if ! probe=$(ssh_exec_powershell "$(doctor_probe_script)" 2>/dev/null | tr -d '\r'); then
		printf 'guest survey: FAILED\n'
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

# Transport selection wrapper functions
# These delegate to SSH if enabled, otherwise fall back to QGA

transport_exec_powershell() {
	if ssh_transport_enabled; then
		ssh_exec_powershell "$@"
	else
		exec_powershell "$@"
	fi
}

transport_exec_argv() {
	if ssh_transport_enabled; then
		ssh_exec_argv "$@"
	else
		exec_argv "$@"
	fi
}

transport_push() {
	if ssh_transport_enabled; then
		# ssh_push takes (local_path, remote_path), cmd_push takes (vmid, local_path, remote_path)
		ssh_push "$2" "$3"
	else
		cmd_push "$@"
	fi
}

transport_pull() {
	if ssh_transport_enabled; then
		# ssh_pull takes (remote_path, local_path), cmd_pull takes (vmid, remote_path, local_path)
		ssh_pull "$2" "${3:-}"
	else
		cmd_pull "$@"
	fi
}

transport_ping() {
	if ssh_transport_enabled; then
		ssh_ping
	else
		cmd_ping "$@"
	fi
}

transport_info() {
	if ssh_transport_enabled; then
		ssh_info
	else
		cmd_info "$@"
	fi
}

transport_doctor() {
	if ssh_transport_enabled; then
		ssh_doctor
	else
		cmd_doctor "$@"
	fi
}

transport_qga_recover() {
	if ssh_transport_enabled; then
		ssh_qga_recover
	else
		qga_recover "$@"
	fi
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

# Transport-aware command requirements
if ssh_transport_enabled; then
	require_command ssh
	require_command scp
else
	require_command pvesh
	require_command qm
fi
require_command jq
require_command iconv
require_command base64
require_command sha256sum
require_command dd

case $SUBCOMMAND in
doctor) transport_doctor "$VMID" ;;
ping) transport_ping "$VMID" ;;
info) transport_info "$VMID" ;;
exec)
	shift 2
	transport_exec_argv "$VMID" "$@"
	;;
powershell)
	shift 2
	[[ $# -ge 1 ]] || die "powershell needs a script to run"
	transport_exec_powershell "$VMID" "$*"
	;;
push)
	shift 2
	[[ $# -eq 2 ]] || die "push needs exactly: <vmid> <local-file> <windows-path>"
	transport_push "$VMID" "$1" "$2"
	;;
pull)
	shift 2
	[[ $# -ge 1 && $# -le 2 ]] || die "pull needs: <vmid> <windows-path> [local-file]"
	transport_pull "$VMID" "$1" "${2:-}"
	;;
detonate)
	shift 2
	[[ $# -ge 1 ]] || die "detonate needs: <vmid> <local-sample> [run-args...]"
	# Inline detonate logic to avoid function definition issues
	local_path=$1
	shift
	[[ -f $local_path ]] || die "no such local sample: $local_path"
	transport_exec_powershell "$VMID" "Write-Output 'transport test'" >/dev/null || die "transport not working for VM $VMID"
	require_running_vm "$VMID"

	name=$(basename "$local_path")
	size=$(wc -c <"$local_path")
	((size > 0)) || die "sample $name is empty"
	sample_hash=$(sha256sum "$local_path" | cut -d' ' -f1)

	ram_mib=$((size / 1048576 + DETONATE_HEADROOM_MIB))
	((ram_mib < DETONATE_MIN_MIB)) && ram_mib=$DETONATE_MIN_MIB
	((ram_mib <= DETONATE_MAX_MIB)) ||
		die "sample needs a ${ram_mib} MiB RAM disk, over the ${DETONATE_MAX_MIB} MiB ceiling"

	free_mib=""
	free_mib=$(transport_exec_powershell "$VMID" \
		"[int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)" |
		tr -d '\r\n[:space:]') || free_mib=""
	[[ $free_mib =~ ^[0-9]+$ ]] || die "could not read free memory in VM $VMID"
	((ram_mib + 512 <= free_mib)) ||
		die "VM $VMID has ${free_mib} MiB free, too little for a ${ram_mib} MiB RAM disk plus headroom"

	note "detonating $name (sha256 ${sample_hash}) in VM $VMID on a ${ram_mib} MiB memory disk"

	letter=""
	letter=$(transport_exec_powershell "$VMID" "$(ramdisk_free_letter_script)" | tr -d '\r\n[:space:]')
	[[ $letter == ?: ]] || die "no free drive letter in VM $VMID"

	# case_dir must be defined before trap uses it for PCAP
	case_dir=""
	case_dir="$ARTIFACT_DIR/$(date -u +%Y%m%dT%H%M%SZ)-${name%.*}"
	mkdir -p "$case_dir" || die "cannot create the case directory $case_dir"

	# Start PCAP capture on host tap interface for this VM's network
	PCAP_FILE="$case_dir/network.pcap"
	note "starting PCAP capture on vmbr1 to $PCAP_FILE"
	timeout 3600 tcpdump -i vmbr1 -s 0 -w "$PCAP_FILE" "ether host $(qm config "$VMID" | awk -F= '/^net0:/{print $2}' | cut -d, -f1)" &
	PCAP_PID=$!

	DETONATE_VMID=$VMID DETONATE_LETTER=$letter DETONATE_SAMPLE=$name
	# Inline cleanup trap to avoid function definition issues
	trap '
		rc=0
		# Stop PCAP capture
		if [[ -n ${PCAP_PID:-} ]] && kill -0 $PCAP_PID 2>/dev/null; then
			kill $PCAP_PID
			wait $PCAP_PID 2>/dev/null
			note "PCAP capture saved to $PCAP_FILE"
		fi
		# Escalate rather than reporting failure on the first refusal. A graceful
		# detach is refused whenever anything holds the volume open, and after a
		# detonation that is routinely the guest agent itself: a transfer that timed
		# out leaves it holding the archive we were reading, and its dismount is what
		# fails. Restarting the agent is what releases those handles, and the force
		# flag is the last resort for a volume that is genuinely wedged.
		gone=""
		note "detaching RAM disk $DETONATE_LETTER from VM $DETONATE_VMID"
		transport_exec_powershell "$DETONATE_VMID" "$(ramdisk_detach_script "$DETONATE_LETTER")" >/dev/null 2>&1 || true
		gone=$(transport_exec_powershell "$DETONATE_VMID" "$(
			cat <<EOF
\$ErrorActionPreference = '"'"'SilentlyContinue'"'"'
\$drive = '"'"'$(printf '"'"'%s'"'"' "${DETONATE_LETTER%:}" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"')"
Write-Output ("LETTER_GONE=" + \$(if (Test-Path (\$drive + '"'"':'"'"')) { 0 } else { 1 }))
EOF
		)" 2>/dev/null | tr -d '"'"'\r'"'"' | sed -n '"'"'s/.*LETTER_GONE=\([01]\).*/\1/p'"'"') || gone=""
		if [[ $gone != 1 ]]; then
			note "$DETONATE_LETTER refused a graceful detach; releasing handles held by the guest agent"
			transport_qga_recover "$DETONATE_VMID" || true
			note "waiting for guest agent to fully restart and release handles"
			sleep 8
			transport_exec_powershell "$DETONATE_VMID" "$(ramdisk_detach_script "$DETONATE_LETTER")" >/dev/null 2>&1 || true
			gone=$(transport_exec_powershell "$DETONATE_VMID" "$(
				cat <<EOF
\$ErrorActionPreference = '"'"'SilentlyContinue'"'"'
\$drive = '"'"'$(printf '"'"'%s'"'"' "${DETONATE_LETTER%:}" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"')"
Write-Output ("LETTER_GONE=" + \$(if (Test-Path (\$drive + '"'"':'"'"')) { 0 } else { 1 }))
EOF
			)" 2>/dev/null | tr -d '"'"'\r'"'"' | sed -n '"'"'s/.*LETTER_GONE=\([01]\).*/\1/p'"'"') || gone=""
		fi
		if [[ $gone != 1 ]]; then
			note "$DETONATE_LETTER still attached; forcing removal with retries"
			force_attempt=0
			max_force_attempts=3
			while ((force_attempt < max_force_attempts && gone != 1)); do
				((force_attempt++))
				note "force detach attempt $force_attempt/$max_force_attempts"
				transport_exec_powershell "$DETONATE_VMID" "$(ramdisk_detach_script "$DETONATE_LETTER" D)" >/dev/null 2>&1 || true
				sleep 3
				gone=$(transport_exec_powershell "$DETONATE_VMID" "$(
					cat <<EOF
\$ErrorActionPreference = '"'"'SilentlyContinue'"'"'
\$drive = '"'"'$(printf '"'"'%s'"'"' "${DETONATE_LETTER%:}" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"')"
Write-Output ("LETTER_GONE=" + \$(if (Test-Path (\$drive + '"'"':'"'"')) { 0 } else { 1 }))
EOF
				)" 2>/dev/null | tr -d '"'"'\r'"'"' | sed -n '"'"'s/.*LETTER_GONE=\([01]\).*/\1/p'"'"') || gone=""
			done
		fi
		if [[ $gone == 1 ]]; then
			note "$DETONATE_LETTER is gone; the sample existed only in guest memory"
		else
			note "SEVERE: $DETONATE_LETTER is STILL ATTACHED to VM $DETONATE_VMID."
			note "        the sample is still resident; detach it by hand with"
			note "        aim_ll.exe -D -m $DETONATE_LETTER before the next case."
		fi

		stray=""
		stray=$(transport_exec_powershell "$DETONATE_VMID" "$(ramdisk_stray_script "$DETONATE_SAMPLE")" 2>/dev/null |
			tr -d '"'"'\r'"'"' | sed -n '"'"'s/.*STRAY_COPIES=\([0-9]*\).*/\1/p'"'"') || stray=""
		if [[ -z $stray ]]; then :; elif [[ $stray == 0 ]]; then
			note "verified: no copy of $DETONATE_SAMPLE on guest persistent storage"
		else
			note "WARNING: $stray copy/copies of $DETONATE_SAMPLE reached persistent storage"
		fi
	' EXIT
	transport_exec_powershell "$VMID" "$(ramdisk_attach_script "$letter" "$ram_mib")" >/dev/null 2>&1 || true

	gate=""
	gate=$(transport_exec_powershell "$VMID" "$(ramdisk_gate_script "$letter")" 2>/dev/null | tr -d '\r') || gate=""
	gate=${gate##*$'\n'}
	[[ $gate == *'GATE=VM'* ]] ||
		die "refusing to stage: $letter is not memory-backed (${gate:-Arsenal said nothing})"
	note "memory-backed disk at $letter (${gate#*size=} bytes)"

	fmt=""
	fmt=$(transport_exec_powershell "$VMID" "$(ramdisk_format_script "$letter")" 2>/dev/null | tr -d '\r') || fmt=""
	[[ $fmt == FORMAT=NTFS* ]] || die "could not format the RAM disk: ${fmt:-no answer from the guest}"

	outdir="${letter}\\artifacts"
	transport_exec_powershell "$VMID" "New-Item -ItemType Directory -Path $(ps_quote "${letter}\\sample"),$(ps_quote "$outdir") -Force | Out-Null" >/dev/null

	transport_push "$VMID" "$local_path" "${letter}\\sample\\$name"

	runout=""
	runout=$(transport_exec_powershell "$VMID" \
		"$(detonate_run_script "$letter" "${letter}\\sample\\$name" "$*" "$outdir")" 2>/dev/null | tr -d '\r') || runout=""
	note "sample finished: ${runout##*$'\n'}"
	runout=""

	collected=""
	collected=$(transport_exec_powershell "$VMID" "$(detonate_collect_script "$letter" "$sample_hash")" 2>/dev/null |
		tr -d '\r') || collected=""
	zipkb=""
	zipkb=$(sed -n 's/^.*ZIP=\([0-9]*\)KiB.*$/\1/p' <<<"$collected")
	[[ -n $zipkb ]] || die "artifact archive was not produced on the RAM disk"
	note "collected $zipkb KiB of evidence into the archive"

	transport_pull "$VMID" "${letter}\\artifacts.zip" "$case_dir/artifacts.zip"

	# Post-pull analysis: YARA + capa if available. The extraction is hoisted
	# out of the yara branch because capa analyses the same directory, and it
	# must not depend on yara being installed to have somewhere to look.
	# Both ship in the agent's package set, so this is currently unreachable,
	# but the ordering is a latent trap rather than a guarantee.
	if command -v yara >/dev/null 2>&1 || command -v capa >/dev/null 2>&1; then
		unzip -q -o "$case_dir/artifacts.zip" -d "$case_dir/extracted"
	fi
	if command -v yara >/dev/null 2>&1; then
		note "running YARA scan on extracted artifacts"
		if [[ -d /etc/yara/rules ]]; then
			yara -r /etc/yara/rules "$case_dir/extracted" >"$case_dir/yara.txt" 2>&1 || true
			note "YARA results: $(grep -c '^' "$case_dir/yara.txt" 2>/dev/null || echo 0) matches"
		else
			note "YARA rules not found at /etc/yara/rules, skipping"
		fi
	fi
	if command -v capa >/dev/null 2>&1; then
		note "running capa capability analysis on sample"
		# capa needs rules - try embedded first, then fall back to /opt/capa-rules
		if capa -V 2>&1 | grep -q "rules embedded"; then
			capa "$case_dir/extracted" >"$case_dir/capa.txt" 2>&1 || true
		elif [[ -d /opt/capa-rules ]]; then
			capa -r /opt/capa-rules "$case_dir/extracted" >"$case_dir/capa.txt" 2>&1 || true
		else
			note "capa rules not found, skipping"
		fi
		# Only claimed when a branch above actually wrote it.
		[[ -f $case_dir/capa.txt ]] &&
			note "capa results written to $case_dir/capa.txt"
	fi

	printf '\n  case:       %s\n  sample:     %s\n  sha256:     %s\n  ram disk:   %s (%s MiB, memory backed)\n  artifacts:  %s\n\n' \
		"$(basename "$case_dir")" "$name" "$sample_hash" "$letter" "$ram_mib" "$case_dir/artifacts.zip"
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
