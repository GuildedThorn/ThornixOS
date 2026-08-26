{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.loom-client;
      mcpServerUrl = "https://loom.guildedthorn.arpa/mcp-server/http";
      configureCodexMcp = pkgs.writeShellApplication {
        name = "configure-codex-loom-mcp";
        runtimeInputs = with pkgs; [
          coreutils
          gawk
        ];
        text = ''
          set -o errexit -o nounset -o pipefail

          codex_home="''${CODEX_HOME:-$HOME/.codex}"
          config_file="$codex_home/config.toml"
          token_file="''${XDG_CONFIG_HOME:-$HOME/.config}/loom/n8n-mcp-token"
          mkdir -p "$codex_home"
          touch "$config_file"

          temporary="$(mktemp "$codex_home/config.toml.XXXXXX")"
          trap 'rm -f "$temporary"' EXIT

          awk -v desired_url=${lib.escapeShellArg mcpServerUrl} -v token_file="$token_file" '
            function emit_url() {
              print "url = \"" desired_url "\""
            }
            function emit_auth() {
              if (have_token) {
                print "http_headers = { Authorization = \"Bearer " bearer "\" }"
              }
            }
            BEGIN {
              in_target = 0
              found_target = 0
              found_url = 0
              found_auth = 0
              have_token = 0
              if ((getline bearer < token_file) > 0) {
                gsub(/[\r\n]/, "", bearer)
                if (bearer !~ /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/) {
                  print "Invalid n8n MCP API key in " token_file > "/dev/stderr"
                  exit 1
                }
                have_token = 1
              }
              close(token_file)
            }
            $0 == "[mcp_servers.n8n]" {
              in_target = 1
              found_target = 1
              print
              next
            }
            in_target && /^\[/ {
              if (!found_url) emit_url()
              if (!found_auth) emit_auth()
              in_target = 0
            }
            in_target && /^[[:space:]]*url[[:space:]]*=/ {
              if (!found_url) emit_url()
              found_url = 1
              next
            }
            in_target && /^[[:space:]]*http_headers[[:space:]]*=/ {
              if (have_token && !found_auth) emit_auth()
              found_auth = 1
              next
            }
            { print }
            END {
              if (in_target && !found_url) emit_url()
              if (in_target && !found_auth) emit_auth()
              if (!found_target) {
                print ""
                print "[mcp_servers.n8n]"
                emit_url()
                emit_auth()
              }
            }
          ' "$config_file" > "$temporary"

          if cmp --silent "$temporary" "$config_file"; then
            exit 0
          fi

          chmod 0600 "$temporary"
          mv -T "$temporary" "$config_file"
          trap - EXIT
        '';
      };
      loomClient = pkgs.writeShellApplication {
        name = "loomctl";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          git
          jq
        ];
        text = ''
          set -o errexit -o nounset -o pipefail

          config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/loom"
          token_file="$config_dir/webhook-token"
          base_url="https://loom.guildedthorn.arpa"

          usage() {
            cat <<'EOF'
          Usage:
            loomctl setup
            loomctl mcp-auth
            loomctl friction [TEXT] [CONTEXT]
            loomctl dump [TEXT]
            loomctl pause [NEXT_STEP] [FAILED_COMMAND]
            loomctl resume [REPOSITORY]
          EOF
          }

          require_token() {
            if [[ ! -s "$token_file" ]]; then
              printf 'Missing %s; run loomctl setup.\n' "$token_file" >&2
              exit 1
            fi
          }

          token() {
            tr -d '\r\n' < "$token_file"
          }

          post() {
            local path=$1
            local payload=$2
            require_token
            curl --silent --show-error --fail-with-body --max-time 15 \
              --config <(printf 'header = "X-Loom-Token: %s"\n' "$(token)") \
              --request POST \
              --header "Content-Type: application/json" \
              --data "$payload" \
              "$base_url/webhook/$path"
          }

          prompt_text() {
            local label=$1
            local value
            read -r -p "$label" value
            printf '%s' "$value"
          }

          command="''${1:-}"
          case "$command" in
            setup)
              mkdir -p "$config_dir"
              chmod 0700 "$config_dir"
              read -r -s -p 'Loom intake token: ' intake_token
              printf '\n'
              if [[ ! "$intake_token" =~ ^[[:xdigit:]]{64}$ ]]; then
                printf 'Token must be 64 hexadecimal characters.\n' >&2
                exit 1
              fi
              install -m 0600 /dev/null "$token_file"
              printf '%s' "$intake_token" > "$token_file"
              printf 'Stored Loom token in %s.\n' "$token_file"
              ;;
            mcp-auth)
              mcp_token_file="$config_dir/n8n-mcp-token"
              mkdir -p "$config_dir"
              chmod 0700 "$config_dir"
              read -r -s -p 'n8n MCP API key: ' mcp_token
              printf '\n'
              if [[ ! "$mcp_token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
                printf 'API key is not a valid JWT.\n' >&2
                exit 1
              fi
              install -m 0600 /dev/null "$mcp_token_file"
              printf '%s' "$mcp_token" > "$mcp_token_file"
              unset mcp_token
              configure-codex-loom-mcp
              printf 'Stored n8n MCP authentication and refreshed Codex.\n'
              ;;
            friction)
              text="''${2:-}"
              context="''${3:-}"
              [[ -n "$text" ]] || text="$(prompt_text 'Friction: ')"
              payload="$(jq -cn --arg text "$text" --arg context "$context" '{text: $text, context: $context}')"
              post thorn-friction "$payload" >/dev/null
              printf 'Friction captured. Loom stays quiet until it repeats.\n'
              ;;
            dump)
              text="''${2:-}"
              [[ -n "$text" ]] || text="$(prompt_text 'Park thought: ')"
              payload="$(jq -cn --arg text "$text" '{text: $text}')"
              post thorn-night-dump "$payload" >/dev/null
              printf 'Thought parked until morning.\n'
              ;;
            pause)
              next_step="''${2:-}"
              failed_command="''${3:-}"
              [[ -n "$next_step" ]] || next_step="$(prompt_text 'Exact next step: ')"
              if ! repo="$(git rev-parse --show-toplevel 2>/dev/null)"; then
                printf 'loomctl pause must run inside a Git worktree.\n' >&2
                exit 1
              fi
              repo_name="$(basename "$repo")"
              branch="$(git branch --show-current)"
              head="$(git log -1 --format='%h %s' 2>/dev/null || true)"
              status="$(git status --short)"
              diff_stat="$({
                git diff --stat
                git diff --cached --stat
              })"
              payload="$(jq -cn \
                --arg repo "$repo" \
                --arg repoName "$repo_name" \
                --arg branch "$branch" \
                --arg head "$head" \
                --arg status "$status" \
                --arg diffStat "$diff_stat" \
                --arg failedCommand "$failed_command" \
                --arg nextStep "$next_step" \
                '{repo: $repo, repoName: $repoName, branch: $branch, head: $head, status: $status, diffStat: $diffStat, failedCommand: $failedCommand, nextStep: $nextStep}')"
              post thorn-restart-capsule "$payload" >/dev/null
              printf 'Restart capsule saved for %s.\n' "$repo_name"
              ;;
            resume)
              require_token
              wanted="''${2:-}"
              if [[ -z "$wanted" ]]; then
                wanted="$(git rev-parse --show-toplevel 2>/dev/null || true)"
              fi
              response="$(curl --silent --show-error --fail-with-body --max-time 15 \
                --config <(printf 'header = "X-Loom-Token: %s"\n' "$(token)") \
                --get \
                --data-urlencode "repo=$wanted" \
                "$base_url/webhook/thorn-restart-capsule-latest")"
              if ! jq -e '.ok == true' >/dev/null <<<"$response"; then
                jq -r '.error // "No restart capsule found."' <<<"$response" >&2
                exit 1
              fi
              jq -r '.capsule | [
                "Repository: \(.repo)",
                "Branch:     \(.branch)",
                "HEAD:       \(.head // "")",
                "Paused:     \(.capturedAt)",
                "Next:       \(.nextStep)",
                (if (.failedCommand // "") != "" then "Failed:     \(.failedCommand)" else empty end),
                "",
                "Working tree:",
                (if (.status // "") != "" then .status else "clean" end),
                "",
                "Diff stat:",
                (if (.diffStat // "") != "" then .diffStat else "none" end)
              ] | join("\n")' <<<"$response"
              ;;
            help|-h|--help)
              usage
              ;;
            *)
              usage >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      options.thorn.programs.loom-client.enable = lib.mkEnableOption "Loom personal workflow client";

      config = lib.mkIf cfg.enable {
        home.packages = [
          configureCodexMcp
          loomClient
        ];

        # Keep both coding-agent clients pointed at Loom without storing an
        # access token in Nix. OpenCode uses n8n's OAuth discovery. Codex can
        # use the instance MCP API key from mutable, mode-0600 user state;
        # the activation helper copies only that value into Codex's own
        # mutable mode-0600 config.
        thorn.programs.opencode.managedSettings.mcp.n8n = {
          type = "remote";
          url = mcpServerUrl;
          enabled = true;
          timeout = 120000;
        };

        # Codex owns a mutable config.toml (project trust, runtime-added MCPs,
        # and tool approval policy). Merge only Loom's endpoint and locally
        # enrolled authentication during activation instead of replacing the
        # rest of that file with a Nix store symlink.
        home.activation.configureCodexLoomMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${configureCodexMcp}/bin/configure-codex-loom-mcp
        '';
      };
    };
}
