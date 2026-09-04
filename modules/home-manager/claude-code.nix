{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.claude-code;

      jq = "${pkgs.jq}/bin/jq";
      git = "${pkgs.git}/bin/git";
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      date = "${pkgs.coreutils}/bin/date";
      stat = "${pkgs.coreutils}/bin/stat";
      cksum = "${pkgs.coreutils}/bin/cksum";

      # Catppuccin Mocha powerline statusline — same palette as stylix's
      # base16Scheme (modules/users/thorn.nix), rendered as 24-bit-color
      # powerline segments. The separator/branch/Nix glyphs are Nerd Font
      # codepoints (GeistMono Nerd Font, installed fleet-wide via
      # modules/users/thorn.nix: U+E0B0 powerline separator, U+E0A0 branch,
      # U+F313 Nix snowflake); everything else is plain emoji/unicode so it
      # degrades gracefully without the patched font.
      statusline = pkgs.writeShellScriptBin "claude-statusline" ''
        #!/usr/bin/env bash
        input=$(cat)

        model=$(${jq} -r '.model.display_name // "?"' <<<"$input")
        dir=$(${jq} -r '.workspace.current_dir // .workspace.project_dir // .cwd // "."' <<<"$input")
        session_id=$(${jq} -r '.session_id // "nosession"' <<<"$input")
        style=$(${jq} -r '.output_style.name // "default"' <<<"$input")
        used_pct=$(${jq} -r '.context_window.used_percentage // empty' <<<"$input")
        cost=$(${jq} -r '.cost.total_cost_usd // 0' <<<"$input")
        duration_ms=$(${jq} -r '.cost.total_duration_ms // 0' <<<"$input")
        lines_added=$(${jq} -r '.cost.total_lines_added // 0' <<<"$input")
        lines_removed=$(${jq} -r '.cost.total_lines_removed // 0' <<<"$input")
        rate_5h=$(${jq} -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
        agent_name=$(${jq} -r '.agent.name // empty' <<<"$input")
        worktree_name=$(${jq} -r '.worktree.name // empty' <<<"$input")

        dirname_display=$(basename "$dir")

        # Catppuccin Mocha, as R;G;B triples for `ESC[3/48;2;R;G;Bm`
        crust='17;17;27'
        surface1='69;71;90'
        surface2='88;91;112'
        subtext0='166;173;200'
        mauve='203;166;247'
        blue='137;180;250'
        teal='148;226;213'
        sky='137;220;235'
        green='166;227;161'
        yellow='249;226;175'
        peach='250;179;135'
        red='243;139;168'
        lavender='180;190;254'
        sapphire='116;199;236'

        fg() { printf '\033[38;2;%sm' "$1"; }
        bg() { printf '\033[48;2;%sm' "$1"; }
        reset=$'\033[0m'
        sep=$''          # nf powerline right triangle
        branch_icon=$''  # nf powerline branch
        nix_icon=$''     # nf Nix snowflake

        prev_bg=""
        line=""

        seg_open() {
          local bgc=$1
          if [ -n "$prev_bg" ]; then
            line+="$(fg "$prev_bg")$(bg "$bgc")$sep"
          else
            line+="$(bg "$bgc")"
          fi
          line+=" "
          prev_bg=$bgc
        }

        seg_close() { line+=" $reset"; }

        seg() {
          seg_open "$1"
          line+="$(fg "$2")$3"
          seg_close
        }

        end_line() {
          [ -n "$prev_bg" ] && line+="$(fg "$prev_bg")$sep$reset"
        }

        # git branch + dirty status, cached per session for up to 5s so a
        # `git status` walk doesn't run on every statusline refresh (this
        # fires after every assistant message) in large repos
        branch=""
        is_dirty=0
        if ${git} -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          cache_dir="''${TMPDIR:-/tmp}/claude-statusline"
          ${mkdir} -p "$cache_dir"
          dir_hash=$(printf '%s' "$dir" | ${cksum} | cut -d' ' -f1)
          cache_file="$cache_dir/$session_id-$dir_hash"
          cache_age=999
          if [ -f "$cache_file" ]; then
            cache_age=$(( $(${date} +%s) - $(${stat} -c %Y "$cache_file" 2>/dev/null || echo 0) ))
          fi
          if [ "$cache_age" -ge 5 ]; then
            branch=$(${git} -C "$dir" branch --show-current 2>/dev/null || true)
            if [ -z "$branch" ]; then
              branch=$(${git} -C "$dir" rev-parse --short HEAD 2>/dev/null || true)
            fi
            is_dirty=0
            if [ -n "$(${git} -C "$dir" status --porcelain 2>/dev/null || true)" ]; then
              is_dirty=1
            fi
            printf '%s|%s\n' "$branch" "$is_dirty" > "$cache_file"
          fi
          IFS='|' read -r branch is_dirty < "$cache_file"
        fi

        # ---- line 1: identity ----
        seg "$mauve" "$crust" "$nix_icon $model"
        seg "$blue" "$crust" "📁 $dirname_display"
        if [ -n "$branch" ]; then
          git_bg=$green
          dirty_mark=""
          [ "$is_dirty" = "1" ] && git_bg=$peach && dirty_mark=" ±"
          seg "$git_bg" "$crust" "$branch_icon $branch$dirty_mark"
        fi
        if [ -n "$style" ] && [ "$style" != "default" ] && [ "$style" != "null" ]; then
          seg "$surface1" "$subtext0" "$style"
        fi
        if [ -n "$worktree_name" ] && [ "$worktree_name" != "null" ]; then
          seg "$sapphire" "$crust" "$branch_icon wt:$worktree_name"
        fi
        if [ -n "$agent_name" ] && [ "$agent_name" != "null" ]; then
          seg "$lavender" "$crust" "🤖 $agent_name"
        fi
        end_line
        line1="$line"

        # ---- line 2: stats ----
        prev_bg=""
        line=""

        if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
          pct_int=$(printf '%.0f' "$used_pct" 2>/dev/null || echo 0)
          if [ "$pct_int" -ge 80 ]; then
            ctx_bg=$red
          elif [ "$pct_int" -ge 50 ]; then
            ctx_bg=$yellow
          else
            ctx_bg=$green
          fi
          seg "$ctx_bg" "$crust" "🧠 $pct_int% ctx"
        fi

        secs_total=$(( duration_ms / 1000 ))
        mins=$(( secs_total / 60 ))
        secs=$(( secs_total % 60 ))
        duration_display=$(printf '%dm%02ds' "$mins" "$secs")
        cost_display=$(printf '$%.2f' "$cost" 2>/dev/null || echo '$0.00')

        seg "$teal" "$crust" "💲$cost_display"
        seg "$sky" "$crust" "⏱ $duration_display"

        # burn rate ($/hr) — only meaningful once the session has run long
        # enough that dividing by duration isn't just amplifying noise
        if [ "$duration_ms" -ge 30000 ]; then
          burn_rate=$(${jq} -n --argjson cost "$cost" --argjson ms "$duration_ms" -r '($cost / ($ms / 3600000))')
          burn_display=$(printf '$%.2f/hr' "$burn_rate" 2>/dev/null || echo '$0.00/hr')
          burn_bucket=$(${jq} -n --argjson r "$burn_rate" -r 'if $r >= 20 then "red" elif $r >= 8 then "yellow" else "green" end')
          case "$burn_bucket" in
            red) rate_bg=$red ;;
            yellow) rate_bg=$yellow ;;
            *) rate_bg=$green ;;
          esac
          seg "$rate_bg" "$crust" "🔥 $burn_display"
        fi

        if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
          seg_open "$surface1"
          line+="$(fg "$green")+$lines_added$(fg "$subtext0") / $(fg "$red")-$lines_removed"
          seg_close
        fi

        if [ -n "$rate_5h" ] && [ "$rate_5h" != "null" ]; then
          rate_int=$(printf '%.0f' "$rate_5h" 2>/dev/null || echo 0)
          if [ "$rate_int" -ge 80 ]; then
            seg "$red" "$crust" "⚠ 5h $rate_int%"
          fi
        fi

        end_line
        line2="$line"

        printf '%s\n%s\n' "$line1" "$line2"
      '';

      managedSettings = {
        statusLine = {
          type = "command";
          command = "${statusline}/bin/claude-statusline";
          padding = 0;
        };
      };

      managedSettingsFile =
        (pkgs.formats.json { }).generate "claude-code-managed-settings.json"
          managedSettings;
    in
    {
      options.thorn.programs.claude-code.enable =
        lib.mkEnableOption "Thorn's Claude Code Home Manager configuration";

      config = lib.mkIf cfg.enable {
        programs.claude-code = {
          enable = true;
          package = null;
        };

        # ~/.claude/settings.json is also written to at runtime by the app
        # itself (theme, model, enabledPlugins, marketplace installs, ...).
        # Managing it directly via programs.claude-code.settings would turn
        # it into a read-only Nix store symlink and break those in-app
        # writes, so instead we shallow-merge just the Nix-managed keys
        # (currently: statusLine) on top of whatever is already there,
        # every time home-manager activates.
        home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          settingsFile="${config.home.homeDirectory}/.claude/settings.json"
          run mkdir -p "$(dirname "$settingsFile")"
          if [ -f "$settingsFile" ]; then
            run ${jq} -s '.[0] * .[1]' "$settingsFile" "${managedSettingsFile}" > "$settingsFile.tmp"
          else
            run ${jq} '.' "${managedSettingsFile}" > "$settingsFile.tmp"
          fi
          run mv "$settingsFile.tmp" "$settingsFile"
        '';
      };
    };
}
