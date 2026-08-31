# shellcheck shell=bash

usage() {
  cat <<'EOF'
Provision ThornixOS VMs from the mac Proxmox host.

Usage:
  thornix-provision PROFILE [options]

Recommended remote session:
  ssh -A root@172.16.25.3
  thornix-provision pixie

Options:
  --flake URI          Flake URI selecting the named profile output.
                       Default: the shared promoted production branch.
  --identity-file PATH Private SSH key used for bootstrap and final checks.
                       Prefer an ssh-agent for passphrase-protected keys.
  --resume             Resume only a VM previously created by this utility.
  --yes                Accept the destructive confirmation non-interactively.
  -h, --help           Show this help.

Each discovered hosts/<profile>/proxmox.nix file declares the exact VM,
storage and bridge this utility may create. Disko erases only /dev/sda inside
that verified VM. This command never deletes a VM.
EOF

  if [[ -r ${THORNIX_PROFILE_DATA:-} ]] && command -v jq >/dev/null 2>&1; then
    printf '\nAvailable profiles:\n'
    jq -r '
      to_entries[]
      | "  \(.key) (VM \(.value.vmid), \(.value.address), \(.value.cores) vCPU, "
        + "\(.value.memoryMiB) MiB RAM, \(.value.diskGiB) GiB disk)"
    ' "$THORNIX_PROFILE_DATA"
  fi
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -ge 1 ]] || {
  usage >&2
  exit 2
}

readonly profile_name=$1
[[ -r ${THORNIX_PROFILE_DATA:-} ]] || die "provision profile data is missing from the mac system closure"
profile_json=$(jq -c --arg profile "$profile_name" '.[$profile] // empty' "$THORNIX_PROFILE_DATA") ||
  die "could not read provision profile '$profile_name'"
[[ -n $profile_json ]] || {
  available_profiles=$(jq -r 'keys | join(", ")' "$THORNIX_PROFILE_DATA")
  die "unknown profile '$profile_name'; available profiles: $available_profiles"
}

vmid=$(jq -r '.vmid' <<<"$profile_json")
vm_name=$(jq -r '.name' <<<"$profile_json")
vm_ip=$(jq -r '.address' <<<"$profile_json")
vm_gateway=$(jq -r '.gateway' <<<"$profile_json")
prefix_length=$(jq -r '.prefixLength' <<<"$profile_json")
bridge=$(jq -r '.bridge' <<<"$profile_json")
storage=$(jq -r '.storage' <<<"$profile_json")
cores=$(jq -r '.cores' <<<"$profile_json")
memory_mib=$(jq -r '.memoryMiB' <<<"$profile_json")
minimum_memory_mib=$(jq -r '.minimumMemoryMiB' <<<"$profile_json")
disk_gib=$(jq -r '.diskGiB' <<<"$profile_json")
minimum_disk_gib=$(jq -r '.minimumDiskGiB' <<<"$profile_json")
maximum_disk_gib=$(jq -r '.maximumDiskGiB' <<<"$profile_json")
minimum_free_gib=$(jq -r '.minimumFreeGiB' <<<"$profile_json")
iso_volume=$(jq -r '.isoVolume' <<<"$profile_json")
iso_label=$(jq -r '.isoLabel' <<<"$profile_json")
disk_serial=$(jq -r '.diskSerial' <<<"$profile_json")
bootstrap_iso_file_path=$(jq -r '.bootstrapIsoFilePath' <<<"$profile_json")
installer_flake=$(jq -r '.installerFlake' <<<"$profile_json")
default_flake=$(jq -r '.defaultFlake' <<<"$profile_json")
installer_profile=$(jq -r '.installerProfile' <<<"$profile_json")
display_name=$(jq -r '.readiness.displayName' <<<"$profile_json")
readiness_label=$(jq -r '.readiness.label' <<<"$profile_json")
readiness_timeout_seconds=$(jq -r '.readiness.timeoutSeconds' <<<"$profile_json")
admin_ssh_keys=$(jq -r '.adminSshKeys[]' <<<"$profile_json")

readonly profile_json vmid vm_name vm_ip vm_gateway prefix_length bridge storage cores memory_mib minimum_memory_mib
readonly disk_gib minimum_disk_gib maximum_disk_gib minimum_free_gib iso_volume iso_label
readonly disk_serial bootstrap_iso_file_path installer_flake default_flake installer_profile display_name readiness_label
readonly readiness_timeout_seconds
readonly admin_ssh_keys
readonly state_installing="thornix-provision:$profile_name:v1:installing"
readonly state_unverified="thornix-provision:$profile_name:v1:installed-unverified"
readonly state_installed="thornix-provision:$profile_name:v1:installed"
shift

flake="$default_flake"
identity_file=""
resume=false
assume_yes=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --flake)
    [[ $# -ge 2 ]] || die "--flake requires a value"
    flake=$2
    shift 2
    ;;
  --identity-file)
    [[ $# -ge 2 ]] || die "--identity-file requires a path"
    identity_file=$2
    shift 2
    ;;
  --resume)
    resume=true
    shift
    ;;
  --yes)
    assume_yes=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown option: $1"
    ;;
  esac
done

flake_suffix="#$profile_name"
[[ $flake == *"$flake_suffix" ]] || die "--flake must select the #$profile_name output"
flake_base=${flake%"$flake_suffix"}
[[ -n $flake_base ]] || die "invalid flake URI: $flake"

if [[ -n $identity_file ]]; then
  [[ -f $identity_file && -r $identity_file ]] || die "cannot read SSH identity: $identity_file"
  identity_file=$(readlink -f -- "$identity_file")
fi

[[ $(hostname -s) == "mac" ]] || die "this utility may only run on the mac Proxmox host"
while IFS= read -r ca_certificate; do
  [[ -r $ca_certificate ]] ||
    die "$profile_name readiness CA certificate is missing from the mac system closure: $ca_certificate"
done < <(jq -r '.readiness.httpChecks[].caCertificate | select(length > 0)' <<<"$profile_json")

for command_name in arping curl ip jq nix nixos-anywhere ping pvesm qm ssh ssh-add ssh-keygen ssh-keyscan sudo; do
  require_command "$command_name"
done

key_is_authorized() {
  local offered_keys=$1
  local expected_type expected_blob offered_type offered_blob

  while read -r expected_type expected_blob _; do
    while read -r offered_type offered_blob _; do
      if [[ $offered_type == "$expected_type" && $offered_blob == "$expected_blob" ]]; then
        return 0
      fi
    done <<<"$offered_keys"
  done <<<"$admin_ssh_keys"
  return 1
}

if [[ -n $identity_file ]]; then
  offered_keys=$(ssh-keygen -y -f "$identity_file") || die "could not read the SSH identity"
elif [[ -n ${SSH_AUTH_SOCK:-} && -S $SSH_AUTH_SOCK ]]; then
  offered_keys=$(ssh-add -L 2>/dev/null) ||
    die "the SSH agent has no keys; load one of $profile_name's admin keys first"
else
  die "no SSH identity is available; connect with 'ssh -A root@172.16.25.3' or use --identity-file"
fi
key_is_authorized "$offered_keys" ||
  die "the available SSH identity is not authorized by the bootstrap or installed $profile_name host"

arping_command=$(command -v arping)
cmp_command=$(command -v cmp)
install_command=$(command -v install)
mv_command=$(command -v mv)
pvesm_command=$(command -v pvesm)
qm_command=$(command -v qm)
sudo_command=$(command -v sudo)
readonly arping_command cmp_command install_command mv_command pvesm_command qm_command sudo_command

root_command=()
if [[ $EUID -ne 0 ]]; then
  "$sudo_command" -v
  root_command=("$sudo_command" --)
fi

root_run() {
  "${root_command[@]}" "$@"
}

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT
known_hosts="$temporary_directory/known_hosts"
bootstrap_iso=""

realize_bootstrap_iso() {
  local installer_attribute installer_root

  [[ -z $bootstrap_iso ]] || return 0
  installer_attribute="$installer_flake#nixosConfigurations.mac.config.system.build.thornixProvisionInstallerIso-$profile_name"

  note "Realizing the key-only $profile_name bootstrap ISO"
  nix build -L --out-link "$temporary_directory/bootstrap-iso" "$installer_attribute"
  installer_root=$(readlink -f -- "$temporary_directory/bootstrap-iso")
  bootstrap_iso="$installer_root/$bootstrap_iso_file_path"
  [[ -r $bootstrap_iso ]] || die "$profile_name bootstrap ISO output is missing $bootstrap_iso_file_path"
}

ssh_options=(
  -o "UserKnownHostsFile=$known_hosts"
  -o StrictHostKeyChecking=yes
  -o CheckHostIP=yes
  -o ConnectTimeout=10
  -o PasswordAuthentication=no
  -o KbdInteractiveAuthentication=no
  -o PreferredAuthentications=publickey
)
if [[ -n $identity_file ]]; then
  ssh_options+=(
    -o IdentitiesOnly=yes
    -i "$identity_file"
  )
fi

remote() {
  # OpenSSH intentionally assembles the remaining arguments into the remote
  # command; every call site below supplies a fixed command, never user input.
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "root@$vm_ip" "$@"
}

capture_host_key() {
  local phase=$1
  local scan_file="$temporary_directory/host-key.scan"
  local attempt

  : >"$known_hosts"
  note "Waiting for $phase SSH at $vm_ip"
  for ((attempt = 1; attempt <= 60; attempt++)); do
    : >"$scan_file"
    if ssh-keyscan -T 3 -t ed25519 -H "$vm_ip" >"$scan_file" 2>/dev/null && [[ -s $scan_file ]]; then
      mv -- "$scan_file" "$known_hosts"
      printf 'Pinned host key: '
      ssh-keygen -lf "$known_hosts"
      return 0
    fi
    if ((attempt % 6 == 0)); then
      printf 'Still waiting for %s SSH (%d/60)\n' "$phase" "$attempt"
    fi
    sleep 5
  done

  die "$phase did not expose SSH within five minutes; inspect VM $vmid in Proxmox"
}

read_vm_config() {
  root_run "$qm_command" config "$vmid"
}

read_vm_state() {
  root_run "$qm_command" status "$vmid" | awk '{ print $2 }'
}

read_description() {
  local description

  description=$(sed -n 's/^description: //p' <<<"$1")

  # Proxmox percent-encodes colons written through `qm --description` when it
  # renders the VM configuration. Decode only that canonical encoding so a
  # literal "%3A" in an unrelated description remains encoded as "%253A"
  # and cannot be mistaken for one of our ownership markers.
  description=${description//%3A/:}
  description=${description//%3a/:}
  printf '%s\n' "$description"
}

read_neighbor_mac() {
  # Refresh the cache if the bridge exposes guest neighbours there. Some
  # Proxmox bridge/kernel combinations keep only an FDB entry, so absence is
  # not itself proof of a mismatch; a present conflicting entry still is.
  ping -q -c 1 -W 1 -I "$bridge" "$vm_ip" >/dev/null 2>&1 || true
  ip neigh show "$vm_ip" dev "$bridge" |
    awk '{
      for (field = 1; field < NF; field++) {
        if ($field == "lladdr") {
          print $(field + 1)
          exit
        }
      }
    }' |
    tr '[:upper:]' '[:lower:]'
}

assert_managed_vm() {
  local expected_description=$1
  local config_text name_line description_line scsi_line net_line unexpected_devices

  config_text=$(read_vm_config)
  name_line=$(sed -n 's/^name: //p' <<<"$config_text")
  description_line=$(read_description "$config_text")
  scsi_line=$(sed -n 's/^scsi0: //p' <<<"$config_text")
  net_line=$(sed -n 's/^net0: //p' <<<"$config_text")

  [[ $name_line == "$vm_name" ]] || die "VM $vmid is named '$name_line', not '$vm_name'; refusing to touch it"
  [[ $description_line == "$expected_description" ]] ||
    die "VM $vmid does not have the expected thornix-provision state; refusing to touch it"
  [[ $scsi_line == "$storage:"* ]] || die "VM $vmid scsi0 is not on $storage storage"
  [[ $scsi_line == *"serial=$disk_serial"* ]] || die "VM $vmid scsi0 lacks the expected disk serial"
  [[ $scsi_line == *"size=${disk_gib}G"* ]] ||
    die "VM $vmid scsi0 is not the expected $disk_gib GiB disk"
  [[ $net_line == "virtio="* ]] || die "VM $vmid net0 is not a virtio NIC"
  [[ $net_line == *"bridge=$bridge"* ]] || die "VM $vmid net0 is not attached to $bridge"

  unexpected_devices=$(awk -F: '
    /^(ide|sata|scsi|virtio)[0-9]+:/ && $1 != "scsi0" && $1 != "ide2" { print $1 }
  ' <<<"$config_text")
  [[ -z $unexpected_devices ]] ||
    die "VM $vmid has unexpected block devices ($unexpected_devices); refusing to run Disko"
}

ensure_iso_installed() {
  local iso_path=$1

  realize_bootstrap_iso

  if [[ -e $iso_path ]] && root_run "$cmp_command" -s -- "$bootstrap_iso" "$iso_path"; then
    note "Bootstrap ISO is already current"
    return 0
  fi

  note "Installing the key-only $profile_name bootstrap ISO"
  root_run "$install_command" -D -m 0444 -- "$bootstrap_iso" "$iso_path.new"
  root_run "$mv_command" -f -- "$iso_path.new" "$iso_path"
}

confirm_destruction() {
  printf '\nVM profile:       %s\n' "$profile_name"
  printf 'Proxmox VMID:     %s\n' "$vmid"
  printf 'Address:          %s/%s via %s\n' "$vm_ip" "$prefix_length" "$vm_gateway"
  printf 'Virtual hardware: %s vCPU, %s-%s MiB RAM, one %s GiB disk on %s\n' \
    "$cores" "$minimum_memory_mib" "$memory_mib" "$disk_gib" "$storage"
  printf 'Install source:   %s\n' "$flake"
  printf '\nDisko WILL erase /dev/sda inside the verified VM. No VM is ever deleted automatically.\n'

  if $assume_yes; then
    return 0
  fi
  [[ -t 0 ]] || die "refusing a non-interactive destructive run without --yes"

  local answer
  read -r -p "Type $profile_name/$vmid to continue: " answer
  [[ $answer == "$profile_name/$vmid" ]] || die "confirmation did not match"
}

build_install_closure() {
  local disko_attribute system_attribute
  disko_attribute="$flake_base#nixosConfigurations.$profile_name.config.system.build.diskoScript"
  system_attribute="$flake_base#nixosConfigurations.$profile_name.config.system.build.toplevel"

  note "Building the exact $profile_name closure before changing Proxmox"
  nix build -L --out-link "$temporary_directory/disko" "$disko_attribute"
  nix build -L --out-link "$temporary_directory/system" "$system_attribute"

  disko_script=$(readlink -f -- "$temporary_directory/disko")
  nixos_system=$(readlink -f -- "$temporary_directory/system")
  [[ -x $disko_script ]] || die "Disko output is not executable: $disko_script"
  [[ -d $nixos_system ]] || die "NixOS system output is not a directory: $nixos_system"
}

verify_installer() {
  local config_text vm_mac observed_mac remote_mac marker disk_inventory disk_names disk_size remote_disk_serial remote_iso_label
  local minimum_size=$((minimum_disk_gib * 1024 * 1024 * 1024))
  local maximum_size=$((maximum_disk_gib * 1024 * 1024 * 1024))

  note "Authenticating and verifying the installer target"
  remote true

  config_text=$(read_vm_config)
  vm_mac=$(sed -n 's/^net0: virtio=\([^,]*\).*/\1/p' <<<"$config_text" | tr '[:upper:]' '[:lower:]')
  observed_mac=$(read_neighbor_mac)
  remote_mac=$(remote cat /sys/class/net/eth0/address | tr '[:upper:]' '[:lower:]')
  marker=$(remote cat /etc/thornix-installer-profile)
  disk_inventory=$(remote lsblk -dn -o NAME,TYPE)
  disk_names=$(awk '$2 == "disk" { print $1 }' <<<"$disk_inventory")
  disk_size=$(remote blockdev --getsize64 /dev/sda)
  remote_disk_serial=$(remote lsblk -dn -o SERIAL /dev/sda | tr -d '[:space:]')
  # This is deliberately single-quoted: $source must expand on the installer.
  # shellcheck disable=SC2016
  remote_iso_label=$(remote 'source=$(findmnt -rn -o SOURCE /iso) && blkid -s LABEL -o value "$source"')

  [[ -n $vm_mac && $remote_mac == "$vm_mac" ]] ||
    die "MAC mismatch: Proxmox '$vm_mac', installer '$remote_mac'"
  [[ -z $observed_mac || $observed_mac == "$vm_mac" ]] ||
    die "MAC mismatch: Proxmox '$vm_mac', neighbor '$observed_mac', installer '$remote_mac'"
  [[ -n $observed_mac ]] ||
    warn "the bridge has no neighbor-cache entry for $vm_ip; Proxmox and installer MACs still match"
  [[ $marker == "$installer_profile" ]] ||
    die "SSH endpoint is not the Thornix $profile_name installer; Disko was not run"
  [[ $remote_iso_label == "$iso_label" ]] ||
    die "live system is not mounted from the expected bootstrap ISO"
  [[ $disk_names == "sda" ]] ||
    die "expected exactly one disk named sda, found: ${disk_names:-none}"
  [[ $remote_disk_serial == "$disk_serial" ]] ||
    die "/dev/sda serial '$remote_disk_serial' does not match '$disk_serial'"
  [[ $disk_size =~ ^[0-9]+$ ]] || die "could not determine /dev/sda size"
  ((disk_size >= minimum_size && disk_size <= maximum_size)) ||
    die "/dev/sda is $disk_size bytes, outside the guarded $minimum_disk_gib-$maximum_disk_gib GiB range"

  printf 'Verified VM %s, MAC %s, ISO label %s, /dev/sda %s bytes.\n' \
    "$vmid" "$vm_mac" "$remote_iso_label" "$disk_size"
}

reboot_to_installed_system() {
  local attempt

  note "Rebooting $profile_name from the installer into its disk"
  remote systemctl reboot >/dev/null 2>&1 || true

  for ((attempt = 1; attempt <= 60; attempt++)); do
    if ! remote true >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  die "VM $vmid did not leave the installer after its reboot request"
}

readiness_checks_pass() {
  local http_count tftp_count index unit url ca_certificate resolve expect_pattern
  local -a units curl_arguments

  mapfile -t units < <(jq -r '.readiness.units[]' <<<"$profile_json")
  for unit in "${units[@]}"; do
    remote systemctl is-active --quiet "$unit" || return 1
  done

  http_count=$(jq -r '.readiness.httpChecks | length' <<<"$profile_json")
  for ((index = 0; index < http_count; index++)); do
    url=$(jq -r --argjson index "$index" '.readiness.httpChecks[$index].url' <<<"$profile_json")
    ca_certificate=$(jq -r --argjson index "$index" '.readiness.httpChecks[$index].caCertificate' <<<"$profile_json")
    resolve=$(jq -r --argjson index "$index" '.readiness.httpChecks[$index].resolve' <<<"$profile_json")
    expect_pattern=$(jq -r --argjson index "$index" '.readiness.httpChecks[$index].expectPattern' <<<"$profile_json")
    curl_arguments=(
      --fail
      --silent
      --show-error
      --noproxy '*'
      --connect-timeout 3
      --max-time 8
    )
    [[ -z $ca_certificate ]] || curl_arguments+=(--cacert "$ca_certificate")
    [[ -z $resolve ]] || curl_arguments+=(--resolve "$resolve")

    if [[ -n $expect_pattern ]]; then
      curl "${curl_arguments[@]}" -- "$url" | grep -E -- "$expect_pattern" >/dev/null || return 1
    else
      curl "${curl_arguments[@]}" --output /dev/null -- "$url" || return 1
    fi
  done

  tftp_count=$(jq -r '.readiness.tftpChecks | length' <<<"$profile_json")
  for ((index = 0; index < tftp_count; index++)); do
    url=$(jq -r --argjson index "$index" '.readiness.tftpChecks[$index]' <<<"$profile_json")
    curl --fail --silent --show-error --output /dev/null \
      --noproxy '*' \
      --connect-timeout 3 \
      --max-time 15 \
      -- "$url" || return 1
  done
}

verify_installed_system() {
  local config_text vm_mac observed_mac remote_mac hostname_value marker attempt max_attempts

  capture_host_key "installed $profile_name"
  note "Authenticating to the installed system"
  remote true

  config_text=$(read_vm_config)
  vm_mac=$(sed -n 's/^net0: virtio=\([^,]*\).*/\1/p' <<<"$config_text" | tr '[:upper:]' '[:lower:]')
  observed_mac=$(read_neighbor_mac)
  remote_mac=$(remote cat /sys/class/net/eth0/address | tr '[:upper:]' '[:lower:]')
  hostname_value=$(remote hostname -s)
  marker=$(remote 'cat /etc/thornix-installer-profile 2>/dev/null || true')
  [[ -n $vm_mac && $remote_mac == "$vm_mac" ]] ||
    die "MAC mismatch: Proxmox '$vm_mac', installed host '$remote_mac'"
  [[ -z $observed_mac || $observed_mac == "$vm_mac" ]] ||
    die "MAC mismatch: Proxmox '$vm_mac', neighbor '$observed_mac', installed host '$remote_mac'"
  [[ -n $observed_mac ]] ||
    warn "the bridge has no neighbor-cache entry for $vm_ip; Proxmox and installed-host MACs still match"
  [[ $hostname_value == "$vm_name" ]] || die "installed host reports hostname '$hostname_value', not '$vm_name'"
  [[ $marker != "$installer_profile" ]] ||
    die "VM booted back into the installer instead of the installed disk"
  remote test -e /run/current-system
  remote systemctl is-active --quiet sshd.service

  note "Waiting for $readiness_label readiness"
  max_attempts=$(((readiness_timeout_seconds + 4) / 5))
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if readiness_checks_pass; then
      note "Installed $display_name system and configured readiness checks are online"
      return 0
    fi
    if ((attempt % 6 == 0)); then
      printf 'Still waiting for %s (%d/%d)\n' "$readiness_label" "$attempt" "$max_attempts"
    fi
    sleep 5
  done

  die "$readiness_label did not become ready within $readiness_timeout_seconds seconds; inspect VM $vmid"
}

print_ready() {
  printf '\n%s VM %s is marked installed.\n' "$display_name" "$vmid"
  jq -r '.readiness.readyLines[]' <<<"$profile_json"
}

storage_status=$(root_run "$pvesm_command" status --storage "$storage")
storage_state=$(awk -v name="$storage" '$1 == name { print $3 }' <<<"$storage_status")
[[ $storage_state == "active" ]] || die "Proxmox storage '$storage' is not active"
ip link show dev "$bridge" >/dev/null 2>&1 || die "Proxmox bridge '$bridge' does not exist"

iso_path=$(root_run "$pvesm_command" path "$iso_volume")
[[ $iso_path == /var/lib/vz/template/iso/* ]] ||
  die "Proxmox resolved the ISO outside local ISO storage: $iso_path"

vm_exists=false
vm_state="absent"
vm_description=""
if root_run "$qm_command" config "$vmid" >/dev/null 2>&1; then
  vm_exists=true
  vm_config=$(read_vm_config)
  vm_state=$(read_vm_state)
  vm_description=$(read_description "$vm_config")

  $resume || die "VM $vmid already exists; use --resume only if this utility created it"
  case "$vm_description" in
  "$state_installed")
    assert_managed_vm "$state_installed"
    print_ready
    exit 0
    ;;
  "$state_unverified")
    assert_managed_vm "$state_unverified"
    note "Resuming post-install verification without running Disko"
    root_run "$qm_command" set "$vmid" --boot "order=scsi0"
    if [[ $vm_state == "stopped" ]]; then
      root_run "$qm_command" start "$vmid"
    elif [[ $vm_state != "running" ]]; then
      die "VM $vmid is in unexpected state '$vm_state'"
    fi

    # An interruption after installation but before the reboot leaves the VM
    # safely in the installer. Reboot it into the already-installed disk;
    # never send this state back through nixos-anywhere or Disko.
    capture_host_key "unverified $profile_name"
    remote true
    current_marker=$(remote 'cat /etc/thornix-installer-profile 2>/dev/null || true')
    if [[ $current_marker == "$installer_profile" ]]; then
      reboot_to_installed_system
    fi
    verify_installed_system
    if ! root_run "$qm_command" set "$vmid" --delete ide2; then
      warn "$profile_name is installed, but the bootstrap ISO could not be detached"
    fi
    root_run "$qm_command" set "$vmid" --description "$state_installed"
    print_ready
    exit 0
    ;;
  "$state_installing")
    assert_managed_vm "$state_installing"
    ;;
  *)
    die "VM $vmid was not created by thornix-provision; refusing to touch it"
    ;;
  esac
else
  $resume && die "--resume was requested, but VM $vmid does not exist"
fi

if ! $vm_exists; then
  storage_free_kib=$(awk -v name="$storage" '$1 == name { print $6 }' <<<"$storage_status")
  [[ $storage_free_kib =~ ^[0-9]+$ ]] || die "could not determine free space on '$storage'"
  ((storage_free_kib >= minimum_free_gib * 1024 * 1024)) ||
    die "storage '$storage' has less than the guarded $minimum_free_gib GiB free-space minimum"

  note "Checking that $vm_ip is unused on $bridge"
  if ! root_run "$arping_command" -D -q -c 3 -w 5 -I "$bridge" "$vm_ip"; then
    die "$vm_ip answered duplicate-address detection; refusing to create $profile_name"
  fi
fi

# Both derivations are realized before confirmation or VM creation. A missing
# production branch, evaluation failure, or cache/build failure therefore cannot
# leave behind a half-created guest or an erased disk.
build_install_closure
confirm_destruction

if ! $vm_exists; then
  ensure_iso_installed "$iso_path"

  note "Creating guarded Proxmox VM $vmid"
  root_run "$qm_command" create "$vmid" \
    --name "$vm_name" \
    --description "$state_installing" \
    --ostype l26 \
    --bios seabios \
    --cpu x86-64-v2-AES \
    --sockets 1 \
    --cores "$cores" \
    --memory "$memory_mib" \
    --balloon "$minimum_memory_mib" \
    --scsihw virtio-scsi-single \
    --scsi0 "$storage:$disk_gib,discard=on,iothread=1,ssd=1,serial=$disk_serial" \
    --net0 "virtio,bridge=$bridge,firewall=1" \
    --agent enabled=1 \
    --onboot 1
  vm_exists=true
  vm_state="stopped"
else
  note "Resuming thornix-provision VM $vmid"
fi

if [[ $vm_state == "stopped" ]]; then
  ensure_iso_installed "$iso_path"
  root_run "$qm_command" set "$vmid" --ide2 "$iso_volume,media=cdrom"
  root_run "$qm_command" set "$vmid" --boot "order=ide2;scsi0"
elif [[ $vm_state == "running" ]]; then
  running_config=$(read_vm_config)
  ide2_line=$(sed -n 's/^ide2: //p' <<<"$running_config")
  [[ $ide2_line == *"$iso_volume"* && $ide2_line == *"media=cdrom"* ]] ||
    die "running VM $vmid is not using the expected bootstrap ISO"
else
  die "VM $vmid is in unexpected state '$vm_state'"
fi

assert_managed_vm "$state_installing"
if [[ $vm_state == "stopped" ]]; then
  note "Starting $profile_name from the bootstrap ISO"
  root_run "$qm_command" start "$vmid"
fi

capture_host_key "$profile_name installer"
verify_installer

# Make the installed disk the sole boot target before installation. Proxmox can
# assign the attached ISO a lower QEMU boot index even when it appears second in
# an ordered list, which boots back into the installer after a successful Disko
# run. The ISO remains attached for explicit console recovery until validation.
root_run "$qm_command" set "$vmid" --boot "order=scsi0"

note "Installing the prebuilt ThornixOS $profile_name closure"
anywhere_arguments=(
  --store-paths "$disko_script" "$nixos_system"
  --target-host "root@$vm_ip"
  --phases "disko,install"
  -L
  --ssh-option "UserKnownHostsFile=$known_hosts"
  --ssh-option StrictHostKeyChecking=yes
  --ssh-option CheckHostIP=yes
  --ssh-option PasswordAuthentication=no
  --ssh-option KbdInteractiveAuthentication=no
)
if [[ -n $identity_file ]]; then
  anywhere_arguments+=(-i "$identity_file")
fi

if ! nixos-anywhere "${anywhere_arguments[@]}"; then
  printf '\nInstallation stopped safely. VM %s was left intact for inspection.\n' "$vmid" >&2
  printf 'After correcting the error, rerun: thornix-provision %s --resume\n' "$profile_name" >&2
  exit 1
fi

# Installation has completed while the verified installer is still running.
# Change the persistent Proxmox state before requesting a reboot. From this
# point onward, --resume is verification-only and can never rerun Disko.
root_run "$qm_command" set "$vmid" --description "$state_unverified"
reboot_to_installed_system
verify_installed_system

if ! root_run "$qm_command" set "$vmid" --delete ide2; then
  warn "$profile_name is installed, but the bootstrap ISO could not be detached"
fi
root_run "$qm_command" set "$vmid" --description "$state_installed"

print_ready
