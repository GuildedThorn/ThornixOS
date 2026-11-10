set -o errexit -o nounset -o pipefail

state_dir=/var/lib/stalwart
certificate_dir=/var/lib/acme/courier.guildedthorn.arpa
recovery_port=18082
recovery_unit=stalwart-recovery.service

if [[ $EUID -ne 0 ]]; then
  echo 'error: run courier-reconcile-stalwart as root' >&2
  exit 1
fi
for required_file in \
  "$state_dir/config.json" \
  "$state_dir/bootstrap-admin-password" \
  "$certificate_dir/fullchain.pem" \
  "$certificate_dir/key.pem"; do
  if [[ ! -s "$required_file" ]]; then
    echo "error: required file is missing or empty: $required_file" >&2
    exit 1
  fi
done
if ! systemctl is-active --quiet stalwart.service; then
  echo 'error: stalwart.service must be running before reconciliation' >&2
  exit 1
fi

binary="$(readlink -f "/proc/$(systemctl show -p MainPID --value stalwart.service)/exe")"

cleanup() {
  status=$?
  trap - EXIT INT TERM
  systemctl stop "$recovery_unit" >/dev/null 2>&1 || true
  rm -f /run/stalwart-recovery.env
  systemctl start stalwart.service
  exit "$status"
}
trap cleanup EXIT INT TERM

run_cli() {
  STALWART_URL="http://127.0.0.1:$recovery_port" \
    STALWART_USER=admin \
    STALWART_PASSWORD="$recovery_password" \
    stalwart-cli "$@"
}

systemctl stop stalwart.service
backup_dir="/var/lib/stalwart-pre-reconcile-$(date -u +%Y%m%dT%H%M%SZ)"
cp -a "$state_dir" "$backup_dir"
echo "Created stopped-state backup: $backup_dir"

recovery_password="$(tr -d '\n' < "$state_dir/bootstrap-admin-password")"
umask 0077
printf 'STALWART_RECOVERY_ADMIN=admin:%s\n' "$recovery_password" \
  > /run/stalwart-recovery.env

systemd-run --quiet \
  --unit="${recovery_unit%.service}" \
  --property=Type=simple \
  --property=User=stalwart \
  --property=Group=stalwart \
  --property=WorkingDirectory="$state_dir" \
  --property=EnvironmentFile=/run/stalwart-recovery.env \
  --setenv=STALWART_RECOVERY_MODE=true \
  --setenv="STALWART_RECOVERY_MODE_PORT=$recovery_port" \
  --setenv=STALWART_HOSTNAME=courier.guildedthorn.arpa \
  "$binary" --config="$state_dir/config.json"
rm -f /run/stalwart-recovery.env

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$recovery_port/healthz/live" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS "http://127.0.0.1:$recovery_port/healthz/live" >/dev/null

certificate_json='{"certificate":{"@type":"File","filePath":"/var/lib/acme/courier.guildedthorn.arpa/fullchain.pem"},"privateKey":{"@type":"File","filePath":"/var/lib/acme/courier.guildedthorn.arpa/key.pem"}}'
certificate_listing="$(run_cli query Certificate \
  --fields subjectAlternativeNames,issuer,notValidAfter --json)"
certificate_id="$(printf '%s\n' "$certificate_listing" \
  | grep -F 'courier.guildedthorn.arpa' \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' \
  | head -n 1 || true)"

if [[ -z "$certificate_id" ]]; then
  run_cli create Certificate --json "$certificate_json"
  certificate_listing="$(run_cli query Certificate \
    --fields subjectAlternativeNames,issuer,notValidAfter --json)"
  certificate_id="$(printf '%s\n' "$certificate_listing" \
    | grep -F 'courier.guildedthorn.arpa' \
    | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' \
    | head -n 1 || true)"
else
  run_cli update Certificate "$certificate_id" --json "$certificate_json"
fi

if [[ -z "$certificate_id" ]]; then
  echo 'error: Courier certificate was not materialized in the registry' >&2
  exit 1
fi

run_cli update SystemSettings singleton \
  --field "defaultCertificateId=$certificate_id"

listener_listing="$(run_cli query NetworkListener \
  --fields name,bind,protocol,useTls,tlsImplicit --json)"
listener_id="$(printf '%s\n' "$listener_listing" \
  | grep -F '"name":"submission"' \
  | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' \
  | head -n 1 || true)"
listener_json='{"bind":{"[::]:587":true},"protocol":"smtp","useTls":true,"tlsImplicit":false}'

if [[ -z "$listener_id" ]]; then
  run_cli create NetworkListener --json \
    '{"name":"submission","bind":{"[::]:587":true},"protocol":"smtp","useTls":true,"tlsImplicit":false}'
else
  run_cli update NetworkListener "$listener_id" --json "$listener_json"
fi

echo 'Certificate registry object:'
run_cli query Certificate \
  --fields subjectAlternativeNames,issuer,notValidAfter --json
echo 'Submission listener registry object:'
run_cli query NetworkListener --where name=submission \
  --fields name,bind,protocol,useTls,tlsImplicit --json
echo 'Stalwart reconciliation complete; restarting the production service.'

unset recovery_password
