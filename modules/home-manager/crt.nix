{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.desktop.crt;

      # SOC stack endpoints (see modules/computers/soc.nix); Loki is what
      # every host's promtail already pushes to, Prometheus is LAN-reachable.
      lokiUrl = "http://soc.guildedthorn.arpa:3100";
      promUrl = "http://soc.guildedthorn.arpa:9090";

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
            curl -sf --max-time 6 "${promUrl}/api/v1/query" --data-urlencode "query=$1" \
              | jq -r '.data.result[0].value[1] // "0"' || echo "?"
          }

          loki_q() {
            curl -sf --max-time 6 -G "${lokiUrl}/loki/api/v1/query" --data-urlencode "query=$1" \
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
              logcli query --tail --no-labels --output=raw --limit=5 \
                --addr="${lokiUrl}" "$query" 2>/dev/null \
                | sed -u "s/^/$tag|/" || true
              sleep 15
            done
          }

          {
            tag_tail AUD '{job="systemd-journal", unit!~"loki.service|grafana.service"} |~ "key=.?(priv-exec|identity|privilege|modules|time-change)"' &
            tag_tail SSH '{job="systemd-journal", unit="sshd.service"} |~ "Failed password|Invalid user|authentication failure"' &
            tag_tail IDS '{job="suricata"} | json | event_type = "alert" | alert_severity <= 2 | line_format "[sev{{.alert_severity}}] {{.alert_signature}} {{.src_ip}} -> {{.dest_ip}}"' &
            tag_tail CNY '{job="systemd-journal", unit!~"loki.service|grafana.service"} |= "siem-canary-probe"' &
            wait
          } | {
            lines=()
            while IFS= read -r raw; do
              tag="''${raw%%|*}"
              text="''${raw#*|}"
              text="''${text:0:220}"
              entry="$(jq -cn --arg tag "$tag" --arg ts "$(date +%H:%M:%S)" --arg text "$text" \
                '{tag: $tag, ts: $ts, text: $text}')"
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
                     :text "''${entry.ts} ''${entry.text}"))))

        (defwidget display []
          (box :class "root" :orientation "v" :space-evenly false
            (box :class "header" :space-evenly false
              (label :class "title" :halign "start" :text "SOC // GUILDEDTHORN.ARPA")
              (box :hexpand true)
              (label :class "clock" :halign "end" :text clock))
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
          padding: 14px 38px;
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

        .tiles {
          margin-top: 8px;
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

        home.packages = [
          socStats
          socFeed
        ];
      };
    };
}
