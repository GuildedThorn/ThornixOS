#!@bash@
set -o errexit -o nounset -o pipefail

token="$(@postgresql@/bin/psql \
  --host=/run/postgresql \
  --dbname=n8n \
  --username=n8n \
  --no-align \
  --tuples-only \
  --command="SELECT \"apiKey\" FROM user_api_keys WHERE audience = 'mcp-server-api' ORDER BY \"updatedAt\" DESC LIMIT 1;")"
token="$(@coreutils@/bin/printf '%s' "$token" | @coreutils@/bin/tr -d '\r\n')"
if [[ ! "$token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
  echo "error: n8n MCP access must be enabled once in the owner settings" >&2
  exit 1
fi

@coreutils@/bin/printf '%s' "$token" > @modelCredentialDirectory@/n8n-mcp-token.new
unset token
@coreutils@/bin/chmod 0400 @modelCredentialDirectory@/n8n-mcp-token.new
if ! @diffutils@/bin/cmp --silent \
  @modelCredentialDirectory@/n8n-mcp-token.new \
  @modelCredentialDirectory@/n8n-mcp-token; then
  @coreutils@/bin/mv -T \
    @modelCredentialDirectory@/n8n-mcp-token.new \
    @modelCredentialDirectory@/n8n-mcp-token
else
  @coreutils@/bin/rm -f @modelCredentialDirectory@/n8n-mcp-token.new
fi
