{ inputs, ... }:
{
  homeManager.modules.thorn =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.desktop.crt;
      hyprlandPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

      # nginx exposes only the read APIs to this ThornCloud_CA client
      # identity. The key is workstation-scoped in sops; it cannot push or
      # delete telemetry even if one of these helpers is abused.
      lokiUrl = "https://soc.guildedthorn.arpa:3100";
      promUrl = "https://soc.guildedthorn.arpa:9090";
      telemetryReaderCertificate = "${inputs.self}/certs/telemetry-reader.crt";
      telemetryReaderKey = osConfig.sops.secrets.telemetry_reader_key.path;
      telemetryCaBundle = osConfig.security.pki.caBundle;

      # Threshold alerts remain Grafana's real-time path. This scheduled pass
      # gives an analyst model a bounded cross-source window so it can spot
      # first-seen behavior and inconsistencies that static rules miss.
      siemReview = pkgs.writeShellScriptBin "siem-review" ''
        #!${pkgs.runtimeShell}
        set -u

        LOKI=${lib.escapeShellArg lokiUrl}
        PROM=${lib.escapeShellArg promUrl}
        WINDOW=9h
        VAULT_LOG=${lib.escapeShellArg "${config.home.homeDirectory}/Documents/knowledge-base/09 Observability/SIEM Review Log.md"}
        STAMP="$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M')"

        curl_mtls() {
          ${pkgs.curl}/bin/curl \
            --cacert ${lib.escapeShellArg telemetryCaBundle} \
            --cert ${lib.escapeShellArg telemetryReaderCertificate} \
            --key ${lib.escapeShellArg telemetryReaderKey} \
            "$@"
        }

        # Avoid piping curl directly into head: when a response exceeds the
        # model budget, head closes the pipe and curl reports a misleading
        # write failure. Download the server-bounded response first, then
        # apply the byte cap locally.
        bounded_curl() {
          local limit="$1" response result
          shift
          response="$(${pkgs.coreutils}/bin/mktemp --tmpdir siem-review.XXXXXX)" \
            || return 1
          if ! curl_mtls --output "$response" "$@"; then
            ${pkgs.coreutils}/bin/rm -f -- "$response"
            return 1
          fi
          ${pkgs.coreutils}/bin/head -c "$limit" "$response"
          result=$?
          ${pkgs.coreutils}/bin/rm -f -- "$response"
          return "$result"
        }

        # Bound every result before it reaches the model. No telemetry API
        # exposed to this certificate permits writes, deletes, or admin calls.
        loki_instant() {
          bounded_curl 8000 -fsS --max-time 20 -G \
            "$LOKI/loki/api/v1/query" --data-urlencode "query=$1"
        }
        loki_range() {
          bounded_curl 20000 -fsS --max-time 20 -G \
            "$LOKI/loki/api/v1/query_range" \
            --data-urlencode "query=$1" \
            --data-urlencode "since=$WINDOW" \
            --data-urlencode "limit=$2"
        }
        prom() {
          bounded_curl 8000 -fsS --max-time 20 -G \
            "$PROM/api/v1/query" --data-urlencode "query=$1"
        }

        # Query APIs are the only remotely exposed readiness surface. Probe
        # both backends so a partial review cannot be mistaken for success.
        if ! curl_mtls -fsS --max-time 10 --retry 3 --retry-delay 10 \
          --retry-all-errors -G "$LOKI/loki/api/v1/query" \
          --data-urlencode 'query=vector(1)' >/dev/null \
          || ! curl_mtls -fsS --max-time 10 --retry 3 --retry-delay 10 \
          --retry-all-errors -G "$PROM/api/v1/query" \
          --data-urlencode 'query=vector(1)' >/dev/null; then
          ${pkgs.libnotify}/bin/notify-send -u critical "SIEM review" \
            "A protected SOC query endpoint is unreachable; review skipped."
          ${pkgs.coreutils}/bin/mkdir -p \
            "$(${pkgs.coreutils}/bin/dirname "$VAULT_LOG")"
          printf '\n## %s\n\nSTATUS: ALERT — SOC query endpoint unreachable; review skipped.\n' \
            "$STAMP" >> "$VAULT_LOG"
          exit 1
        fi

        DATA=$(
          set -e
          echo '=== per-host journal volume (window) ==='
          loki_instant "sum by (host) (count_over_time({job=\"systemd-journal\"}[$WINDOW]))"
          echo; echo '=== suricata EVE alerts ==='
          loki_range '{job="suricata"} | json | event_type = "alert"' 100
          echo; echo '=== pfSense perimeter suricata priority 1-2 ==='
          loki_range '{job="syslog"} |~ "Priority: [12]"' 50
          echo; echo '=== SSH authentication failures ==='
          loki_range '{job="systemd-journal", unit=~"sshd(-session)?.service"} |~ "Failed password|Invalid user"' 100
          echo; echo '=== CrowdSec scenario hits ==='
          loki_range '{unit="crowdsec.service"} |~ "performed"' 50
          echo; echo '=== audit identity, privilege, modules, and time changes ==='
          loki_range '{job="systemd-journal"} |~ "key=.(identity|privilege|priv-exec|sshd-config|modules|time-change)."' 100
          echo; echo '=== audit-stack high-signal and sensor-health events ==='
          loki_range '{job="systemd-journal", unit=~"(rpc|ipc|session)-auditor.service"} | json | event =~ "container_exec|tunnel_listener_new|inbound_ssh_conn|rpc_listener_new|sensor_exit|cycle_failed|state_save_failed|watcher_failed|watcher_degraded|rate_overflow|cycle_overflow"' 100
          echo; echo '=== Prometheus targets ==='
          prom 'up'
          echo; echo '=== failed systemd units ==='
          prom 'node_systemd_unit_state{state="failed"} == 1'
          echo; echo '=== comin deployment failures ==='
          prom 'comin_last_deployment_failed > 0 or comin_last_build_failed > 0 or comin_last_eval_failed > 0'
        )
        DATA_STATUS=$?
        if (( DATA_STATUS != 0 )); then
          ${pkgs.libnotify}/bin/notify-send -u critical "SIEM review" \
            "A protected SOC query failed; analyst pass skipped."
          ${pkgs.coreutils}/bin/mkdir -p \
            "$(${pkgs.coreutils}/bin/dirname "$VAULT_LOG")"
          printf '\n## %s\n\nSTATUS: ALERT — SOC query failed during review; analyst pass skipped.\n' \
            "$STAMP" >> "$VAULT_LOG"
          exit "$DATA_STATUS"
        fi

        if ! ${pkgs.claude-code}/bin/claude auth status >/dev/null 2>&1; then
          ${pkgs.libnotify}/bin/notify-send -u critical "SIEM review" \
            "Claude CLI authentication is required; run claude auth login."
          ${pkgs.coreutils}/bin/mkdir -p \
            "$(${pkgs.coreutils}/bin/dirname "$VAULT_LOG")"
          printf '\n## %s\n\nSTATUS: ALERT — analyst authentication unavailable; run `claude auth login`.\n' \
            "$STAMP" >> "$VAULT_LOG"
          exit 1
        fi

        VERDICT=$(printf '%s' "$DATA" | ${pkgs.claude-code}/bin/claude -p \
          "You are the scheduled tier-1 SOC review for the ThornixOS homelab fleet. stdin holds the last $WINDOW of bounded Loki and Prometheus data, section-headed. Grafana already pages on hard thresholds, so focus on first-seen behavior, suspicious under-threshold patterns, failed sensors or units, deployment failures, and cross-source inconsistencies. Internet scanner traffic against public services is expected background unless its pattern is unusual. 192.168.1.6 is the administrator's device; port and banner scans from it are normally authorized, but authentication attempts, exploits, or lateral movement are not. Output exactly: first line 'STATUS: OK', 'STATUS: NOTABLE — <reason>', or 'STATUS: ALERT — <reason>'; then 3-8 Markdown bullets, most important first. No preamble." 2>&1)
        ANALYST_STATUS=$?

        if (( ANALYST_STATUS != 0 )); then
          ${pkgs.libnotify}/bin/notify-send -u critical "SIEM review" \
            "Claude analyst invocation failed; review did not complete."
          ${pkgs.coreutils}/bin/mkdir -p \
            "$(${pkgs.coreutils}/bin/dirname "$VAULT_LOG")"
          printf '\n## %s\n\nSTATUS: ALERT — analyst invocation failed; review did not complete.\n' \
            "$STAMP" >> "$VAULT_LOG"
          exit "$ANALYST_STATUS"
        elif [[ -z "$VERDICT" ]]; then
          VERDICT="STATUS: ALERT — analyst pass produced no output."
        fi

        ${pkgs.coreutils}/bin/mkdir -p \
          "$(${pkgs.coreutils}/bin/dirname "$VAULT_LOG")"
        printf '\n## %s\n\n%s\n' "$STAMP" "$VERDICT" >> "$VAULT_LOG"

        FIRST=$(printf '%s' "$VERDICT" | ${pkgs.coreutils}/bin/head -n1)
        case "$FIRST" in
          "STATUS: OK"*) ;;
          "STATUS: NOTABLE"*)
            ${pkgs.libnotify}/bin/notify-send "SIEM review" "''${FIRST#STATUS: }"
            ;;
          *)
            ${pkgs.libnotify}/bin/notify-send -u critical "SIEM review" \
              "''${FIRST#STATUS: }"
            ;;
        esac
      '';

      # One-shot poller: instant queries against Prometheus + Loki, emits a
      # single JSON object for eww's defpoll. Any unreachable backend turns
      # into "?" rather than a crash so the display degrades visibly.
      socStats = pkgs.writeShellApplication {
        name = "crt-soc-stats";
        runtimeInputs = with pkgs; [
          curl
          jq
        ];
        text = ''
          prom_q() {
            curl -sf --max-time 6 \
              --cacert "${telemetryCaBundle}" \
              --cert "${telemetryReaderCertificate}" \
              --key "${telemetryReaderKey}" \
              "${promUrl}/api/v1/query" --data-urlencode "query=$1" \
              | jq -r '.data.result[0].value[1] // "0"' || echo "?"
          }

          loki_q() {
            curl -sf --max-time 6 -G \
              --cacert "${telemetryCaBundle}" \
              --cert "${telemetryReaderCertificate}" \
              --key "${telemetryReaderKey}" \
              "${lokiUrl}/loki/api/v1/query" --data-urlencode "query=$1" \
              | jq -r '.data.result[0].value[1] // "0"' || echo "?"
          }

          nodes_up="$(prom_q 'count(up{job="node"} == 1) OR vector(0)')"
          nodes_total="$(prom_q 'count(up{job="node"}) OR vector(0)')"
          failed_units="$(prom_q 'sum(node_systemd_unit_state{state="failed"}) OR vector(0)')"
          deploy_failed="$(prom_q 'sum(comin_last_deployment_failed) OR vector(0)')"
          ids_1h="$(loki_q 'sum(count_over_time({job="suricata"} | json | event_type = "alert" [1h]))')"
          ssh_1h="$(loki_q 'sum(count_over_time({job="systemd-journal", unit="sshd.service"} |~ "Failed password|Invalid user" [1h]))')"
          # unit exclusion: Loki journals every query it executes, and the
          # canary alert rule's query text itself contains the probe string —
          # without this the canary count would include Loki's own echo.
          canary="$(loki_q 'count(sum by (host) (count_over_time({job="systemd-journal", unit!~"loki.service|grafana.service"} |= "siem-canary-probe" [30m])))')"

          jq -cn \
            --arg nodes_up "$nodes_up" \
            --arg nodes_total "$nodes_total" \
            --arg failed_units "$failed_units" \
            --arg deploy_failed "$deploy_failed" \
            --arg ids_1h "$ids_1h" \
            --arg ssh_1h "$ssh_1h" \
            --arg canary "$canary" \
            '{
              nodes_up: ($nodes_up | tonumber? // $nodes_up),
              nodes_total: ($nodes_total | tonumber? // $nodes_total),
              failed_units: ($failed_units | tonumber? // $failed_units),
              deploy_failed: ($deploy_failed | tonumber? // $deploy_failed),
              ids_1h: ($ids_1h | tonumber? // $ids_1h),
              ssh_1h: ($ssh_1h | tonumber? // $ssh_1h),
              canary: ($canary | tonumber? // $canary)
            }'
        '';
      };

      # Local desktop context for the CRT. A two-second poll keeps this
      # robust across compositor/player/network restarts while still making
      # workspace, media, and connectivity changes feel immediate on a tube.
      desktopState = pkgs.writeShellApplication {
        name = "crt-desktop-state";
        runtimeInputs = [
          hyprlandPackage
          pkgs.coreutils
          pkgs.jq
          pkgs.networkmanager
          pkgs.playerctl
        ];
        text = ''
          workspace="?"
          app="DESKTOP"

          if active_workspace="$(hyprctl activeworkspace -j 2>/dev/null)"; then
            workspace="$(printf '%s' "$active_workspace" | jq -r '.name // (.id | tostring) // "?"')"
          fi

          if active_window="$(hyprctl activewindow -j 2>/dev/null)"; then
            app="$(printf '%s' "$active_window" | jq -r \
              '(.class // "DESKTOP") as $class | (.title // "") as $title |
               if $title == "" then $class else "\($class) · \($title)" end' \
              | cut -c1-46)"
          fi

          media_state="$(playerctl status 2>/dev/null || true)"
          media=""
          if [ "$media_state" = "Playing" ] || [ "$media_state" = "Paused" ]; then
            media="$(playerctl metadata --format '{{title}} · {{artist}}' 2>/dev/null | cut -c1-42 || true)"
          fi

          network_state="$(nmcli -t -f STATE general 2>/dev/null | head -n1 || true)"
          connection="$(nmcli -g NAME connection show --active 2>/dev/null | head -n1 || true)"
          online=false
          case "$network_state" in
            connected*) online=true ;;
          esac
          if [ -n "$connection" ]; then
            network="$connection"
          elif [ -n "$network_state" ]; then
            network="$network_state"
          else
            network="UNKNOWN"
          fi

          jq -cn \
            --arg workspace "$workspace" \
            --arg app "$app" \
            --arg media "$media" \
            --arg media_state "$media_state" \
            --arg network "$network" \
            --argjson online "$online" \
            '{
              workspace: $workspace,
              app: $app,
              media: $media,
              media_state: $media_state,
              network: $network,
              online: $online
            }'
        '';
      };

      # Live feed for eww's deflisten: merges several `logcli --tail`
      # websocket streams (LogQL filters lifted from hosts/soc/dashboards),
      # keeps a rolling buffer, and re-emits it as a JSON array per line.
      socFeed = pkgs.writeShellApplication {
        name = "crt-soc-feed";
        runtimeInputs = with pkgs; [
          grafana-loki
          jq
          gnused
          coreutils
        ];
        text = ''
          tag_tail() {
            local tag="$1" query="$2"
            while true; do
              logcli query --tail --limit=5 --output=jsonl \
                --addr="${lokiUrl}" \
                --ca-cert="${telemetryCaBundle}" \
                --cert="${telemetryReaderCertificate}" \
                --key="${telemetryReaderKey}" \
                "$query" 2>/dev/null \
                | jq --unbuffered -r --arg tag "$tag" \
                    '"\($tag)|\(.labels.host // "?")|\(.line)"' || true
              sleep 15
            done
          }

          # Render a raw kernel audit record down to the fields a human scans
          # for — otherwise the line is all arch=/syscall=/exit= preamble and
          # the interesting part is truncated off the right edge.
          fmt_audit() {
            local line="$1" key comm exe auid argv
            case "$line" in
              EXECVE*)
                argv="$(printf '%s' "$line" | grep -o 'a[0-9]*="[^"]*"' | cut -d'"' -f2 | paste -sd' ' -)"
                printf 'exec %s' "''${argv:-$line}"
                ;;
              SYSCALL*)
                key="$(printf '%s' "$line" | sed -n 's/.*key="\([^"]*\)".*/\1/p')"
                comm="$(printf '%s' "$line" | sed -n 's/.*comm="\([^"]*\)".*/\1/p')"
                exe="$(printf '%s' "$line" | sed -n 's/.* exe="\([^"]*\)".*/\1/p')"
                auid="$(printf '%s' "$line" | sed -n 's/.*auid=\([0-9]*\).*/\1/p')"
                if [ "$auid" = "4294967295" ]; then auid="sys"; fi
                printf '[%s] %s %s uid=%s' "''${key:-?}" "''${comm:-?}" "''${exe:-?}" "''${auid:-?}"
                ;;
              *)
                printf '%s' "$line"
                ;;
            esac
          }

          {
            tag_tail AUD '{job="systemd-journal", unit!~"loki.service|grafana.service"} |~ "key=.?(priv-exec|identity|privilege|modules|time-change)"' &
            tag_tail SSH '{job="systemd-journal", unit="sshd.service"} |~ "Failed password|Invalid user|authentication failure"' &
            tag_tail IDS '{job="suricata"} | json | event_type = "alert" | alert_severity <= 2 | line_format "[sev{{.alert_severity}}] {{.alert_signature}} {{.src_ip}} -> {{.dest_ip}}"' &
            # ^EXECVE keeps the feed to the actual probe execution — the
            # probe's path also appears in audit PATH/SYSCALL records and in
            # nix build output when a deploy rebuilds the probe derivation.
            tag_tail CNY '{job="systemd-journal", unit!~"loki.service|grafana.service"} |= "siem-canary-probe" |~ "^EXECVE"' &
            wait
          } | {
            lines=()
            while IFS= read -r raw; do
              tag="''${raw%%|*}"
              rest="''${raw#*|}"
              host="''${rest%%|*}"
              text="''${rest#*|}"
              case "$tag" in
                # Store-path hashes are 32 chars of noise on a 720px display.
                AUD | CNY) text="$(fmt_audit "$text" | sed 's|/nix/store/[a-z0-9]*-|…/|g')" ;;
              esac
              text="''${text:0:200}"
              entry="$(jq -cn --arg tag "$tag" --arg ts "$(date +%H:%M:%S)" --arg host "$host" --arg text "$text" \
                '{tag: $tag, ts: $ts, host: $host, text: $text}')"
              lines+=("$entry")
              if (( ''${#lines[@]} > 12 )); then
                lines=("''${lines[@]: -12}")
              fi
              printf '%s\n' "''${lines[@]}" | jq -cs '.'
            done
          }
        '';
      };

      ewwYuck = ''
        (defpoll stats :interval "30s"
          :initial '{"nodes_up":"?","nodes_total":"?","failed_units":"?","deploy_failed":"?","ids_1h":"?","ssh_1h":"?","canary":"?"}'
          "crt-soc-stats")

        (defpoll desktop :interval "2s"
          :initial '{"workspace":"?","app":"DESKTOP","media":"","media_state":"Stopped","network":"UNKNOWN","online":false}'
          "crt-desktop-state")

        (deflisten feed :initial "[]" "crt-soc-feed")

        (defpoll clock :interval "1s" "date '+%H:%M:%S'")

        (defwidget tile [label value bad]
          (box :class "tile ''${bad ? 'bad' : 'ok'}" :orientation "v" :space-evenly false
            (label :class "tile-value" :text value)
            (label :class "tile-label" :text label)))

        (defwidget feedview []
          (box :class "feed" :orientation "v" :space-evenly false :vexpand true :valign "end"
            (for entry in feed
              (label :class "feed-line tag-''${entry.tag}" :halign "start" :xalign 0 :truncate true
                     :text "''${entry.ts} ''${entry.host} ''${entry.text}"))))

        (defwidget context-strip []
          (box :class "context" :orientation "v" :space-evenly false :spacing 4
            (box :class "context-row" :space-evenly false :spacing 6
              (label :class "context-chip workspace-state" :text "WS ''${desktop.workspace}")
              (label :class "context-chip app-state" :hexpand true :halign "fill" :xalign 0
                     :truncate true :text {desktop.app})
              (label :class "context-chip network ''${desktop.online ? 'ok' : 'bad'}"
                     :text "NET ''${desktop.network}"))
            (box :class "context-row" :space-evenly false :spacing 6
              (label :class "context-chip media ''${desktop.media_state == 'Playing' ? 'playing' : 'paused'}"
                     :visible {desktop.media != ""} :hexpand true :halign "fill" :xalign 0
                     :truncate true :text "MEDIA ''${desktop.media}")
              (box :hexpand true :visible {desktop.media == ""})
              (label
                :class "context-chip posture ''${
                  stats.nodes_up != stats.nodes_total || stats.failed_units != 0 || stats.deploy_failed != 0 || stats.canary == 0
                    ? 'alert'
                    : stats.ids_1h != 0 || stats.ssh_1h != 0 ? 'watch' : 'ok'
                }"
                :text {stats.nodes_up != stats.nodes_total || stats.failed_units != 0 || stats.deploy_failed != 0 || stats.canary == 0
                  ? "POSTURE ALERT"
                  : stats.ids_1h != 0 || stats.ssh_1h != 0 ? "POSTURE WATCH" : "POSTURE NOMINAL"}))))

        (defwidget display []
          (box :class "root ''${
            stats.nodes_up != stats.nodes_total || stats.failed_units != 0 || stats.deploy_failed != 0 || stats.canary == 0
              ? 'critical'
              : stats.ids_1h != 0 || stats.ssh_1h != 0 ? 'watch' : 'nominal'
          }" :orientation "v" :space-evenly false
            (box :class "header" :space-evenly false
              (label :class "title" :halign "start" :text "THORNIX // SOC")
              (box :hexpand true)
              (label :class "clock" :halign "end" :text clock))
            (context-strip)
            (box :class "tiles" :orientation "v" :space-evenly false :spacing 6
              (box :spacing 6
                (tile :label "NODES UP" :value "''${stats.nodes_up}/''${stats.nodes_total}"
                      :bad {stats.nodes_up != stats.nodes_total})
                (tile :label "UNITS FAILED" :value {stats.failed_units} :bad {stats.failed_units != 0})
                (tile :label "DEPLOY FAILED" :value {stats.deploy_failed} :bad {stats.deploy_failed != 0}))
              (box :spacing 6
                (tile :label "IDS 1H" :value {stats.ids_1h} :bad {stats.ids_1h != 0})
                (tile :label "SSH FAIL 1H" :value {stats.ssh_1h} :bad {stats.ssh_1h != 0})
                (tile :label "CANARY" :value {stats.canary} :bad {stats.canary == 0})))
            (feedview)))

        (defwindow soc-crt
          :monitor "${cfg.monitor}"
          :geometry (geometry :width "100%" :height "100%" :anchor "center")
          :stacking "fg"
          :focusable false
          :exclusive false
          (display))
      '';

      ewwScss = ''
        * {
          all: unset;
          font-family: "JetBrainsMono Nerd Font", monospace;
        }

        /* Sized for the CRT at native 720x480 (scale 1.0): one logical px is
           one scanline, so no fractional-scale blur. The tube shows ~10" of
           a 13" tube, hence the aggressive safe-area padding. */
        .root {
          background-color: #030503;
          color: #46f07d;
          padding: 32px 52px;
          transition: background-color 240ms ease-out,
                      box-shadow 240ms ease-out;
        }

        .root.watch {
          background-color: #070603;
          box-shadow: inset 0 0 28px rgba(255, 180, 84, 0.11);
        }

        .root.critical {
          background-color: #080403;
          box-shadow: inset 0 0 34px rgba(255, 90, 80, 0.16);
        }

        .title {
          font-size: 20px;
          letter-spacing: 2px;
          color: #46f07d;
          text-shadow: 0 0 6px rgba(70, 240, 125, 0.7);
        }

        .clock {
          font-size: 20px;
          color: rgba(70, 240, 125, 0.8);
          text-shadow: 0 0 6px rgba(70, 240, 125, 0.5);
        }

        .context {
          margin-top: 8px;
          font-size: 12px;
        }

        .context-chip {
          min-height: 18px;
          padding: 1px 6px;
          color: rgba(70, 240, 125, 0.72);
          background-color: rgba(70, 240, 125, 0.055);
          border: 1px solid rgba(70, 240, 125, 0.22);
          border-radius: 2px;
          transition: color 180ms ease-out,
                      background-color 180ms ease-out,
                      border-color 180ms ease-out;
        }

        .workspace-state {
          color: #59d6e0;
          border-color: rgba(89, 214, 224, 0.42);
          text-shadow: 0 0 5px rgba(89, 214, 224, 0.45);
        }

        .media.playing {
          color: #b4befe;
          border-color: rgba(180, 190, 254, 0.42);
          text-shadow: 0 0 5px rgba(180, 190, 254, 0.38);
        }

        .network.bad,
        .posture.alert {
          color: #ff5a50;
          border-color: rgba(255, 90, 80, 0.62);
          background-color: rgba(255, 90, 80, 0.08);
          text-shadow: 0 0 6px rgba(255, 90, 80, 0.5);
        }

        .posture.watch {
          color: #ffb454;
          border-color: rgba(255, 180, 84, 0.55);
          background-color: rgba(255, 180, 84, 0.07);
          text-shadow: 0 0 6px rgba(255, 180, 84, 0.45);
        }

        .tiles {
          margin-top: 7px;
        }

        .tile {
          background-color: rgba(70, 240, 125, 0.07);
          border: 1px solid rgba(70, 240, 125, 0.35);
          border-radius: 3px;
          padding: 5px 0;
        }

        .tile-value {
          font-size: 30px;
          text-shadow: 0 0 6px rgba(70, 240, 125, 0.6);
        }

        .tile-label {
          font-size: 13px;
          letter-spacing: 1px;
          color: rgba(70, 240, 125, 0.6);
        }

        .tile.bad {
          border-color: rgba(255, 90, 80, 0.6);
          background-color: rgba(255, 90, 80, 0.08);
        }

        .tile.bad .tile-value {
          color: #ff5a50;
          text-shadow: 0 0 8px rgba(255, 90, 80, 0.7);
        }

        .feed {
          margin-top: 10px;
          font-size: 16px;
        }

        .feed-line {
          color: #39c469;
        }

        .tag-IDS {
          color: #ffb454;
        }

        .tag-SSH {
          color: #ff5a50;
        }

        .tag-CNY {
          color: #59d6e0;
        }
      '';
    in
    {
      options.thorn.desktop.crt = {
        enable = lib.mkEnableOption "eww SOC widget display for the CRT monitor";

        monitor = lib.mkOption {
          type = lib.types.str;
          default = "DP-1";
          description = "Output name the SOC display window opens on.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = builtins.pathExists telemetryReaderCertificate;
            message = ''
              certs/telemetry-reader.crt is missing. Sign the workstation
              reader CSR with ThornCloud_CA before enabling the CRT client.
            '';
          }
        ];

        programs.eww = {
          enable = true;
          yuckConfig = ewwYuck;
          scssConfig = ewwScss;
          # Daemon as a user service. Deliberately NOT hyprland exec-once:
          # with configType = "lua" a dash-keyed settings entry ("exec-once")
          # generates invalid Lua and poisons the whole hyprland config.
          systemd.enable = true;
        };

        systemd.user.services.eww-soc-crt = {
          Unit = {
            Description = "Open the SOC display on the CRT";
            After = [ "eww.service" ];
            BindsTo = [ "eww.service" ];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Retry loop: After= only orders against daemon start, not against
            # its IPC socket being ready.
            ExecStart = "${pkgs.writeShellScript "eww-open-soc-crt" ''
              for _ in $(seq 15); do
                ${config.programs.eww.package}/bin/eww open soc-crt && exit 0
                sleep 1
              done
              exit 1
            ''}";
            ExecStop = "${config.programs.eww.package}/bin/eww close soc-crt";
          };
          Install.WantedBy = [ "eww.service" ];
        };

        systemd.user.services.siem-review = {
          Unit = {
            Description = "Scheduled SIEM log review (Claude analyst pass)";
            After = [ "network-online.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${siemReview}/bin/siem-review";
          };
        };

        systemd.user.timers.siem-review = {
          Unit.Description = "SIEM review three times daily";
          Timer = {
            OnCalendar = [
              "06:52"
              "14:52"
              "22:52"
            ];
            Persistent = true;
            RandomizedDelaySec = "5m";
          };
          Install.WantedBy = [ "timers.target" ];
        };

        home.packages = [
          desktopState
          socStats
          socFeed
          siemReview
        ];
      };
    };
}
