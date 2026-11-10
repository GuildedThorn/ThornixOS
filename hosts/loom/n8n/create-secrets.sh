#!@bash@
set -o errexit -o nounset -o pipefail
umask 0077

for secret_name in encryption-key runner-auth-token; do
  secret_path=@secretStateDirectory@/$secret_name
  if [[ ! -s "$secret_path" ]]; then
    @openssl@/bin/openssl rand -hex 32 \
      | @coreutils@/bin/tr -d '\r\n' > "$secret_path.new"
  else
    # n8n deliberately does not trim _FILE values. Older Loom
    # generations wrote OpenSSL's trailing newline, causing runner
    # authentication warnings and potentially a token mismatch.
    normalized=$(@coreutils@/bin/tr -d '\r\n' < "$secret_path")
    if [[ ! "$normalized" =~ ^[[:xdigit:]]{64}$ ]]; then
      echo "error: refusing to rewrite malformed $secret_path" >&2
      exit 1
    fi
    printf '%s' "$normalized" > "$secret_path.new"
    unset normalized
  fi

  chmod 0400 "$secret_path.new"
  if ! @diffutils@/bin/cmp --silent "$secret_path.new" "$secret_path"; then
    mv -T "$secret_path.new" "$secret_path"
  else
    rm -f "$secret_path.new"
  fi
done
