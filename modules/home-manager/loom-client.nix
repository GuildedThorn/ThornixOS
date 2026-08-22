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
        home.packages = [ loomClient ];
      };
    };
}
