{
  nixos.modules.services-capture-card =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.captureCard;

      preview = pkgs.writeShellApplication {
        name = "elgato-capture-preview";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.hyprland
          pkgs.mpv
          pkgs.systemd
        ];
        text = ''
          set -o errexit -o nounset -o pipefail

          product_pattern=${lib.escapeShellArg cfg.productPattern}
          poll_interval=${toString cfg.pollIntervalSeconds}
          output_name=${lib.escapeShellArg cfg.headlessOutput}
          output_mode=${lib.escapeShellArg cfg.headlessMode}
          output_scale=${toString cfg.headlessScale}
          window_title=${lib.escapeShellArg cfg.windowTitle}

          card_node=""
          preview_pid=""

          # Match on ID_V4L_PRODUCT rather than USB ids: the 4K Capture Pro is a
          # PCIe card behind the sc0710 driver and has no ID_VENDOR_ID at all,
          # so a USB match can never find it. Video node numbering also shifts
          # whenever another capture device appears first, and the matching has
          # to skip v4l2loopback ("OBS Cam"), which carries no identifying
          # properties of its own.
          find_card() {
            local node properties capabilities
            for node in /dev/video*; do
              [[ -e $node ]] || continue
              properties=$(udevadm info --query=property --name="$node" 2>/dev/null) || continue
              grep -qxE "ID_V4L_PRODUCT=$product_pattern" <<<"$properties" || continue
              # udev reports capabilities as a colon-separated list whose exact
              # spelling has changed between systemd releases: viewfinder emits
              # ":capture:", older ones emit "*:capture:*". Matching a list
              # member instead of a literal value covers both, and also
              # excludes metadata-only nodes from the same device.
              capabilities=$(grep -m1 '^ID_V4L_CAPABILITIES=' <<<"$properties" || true)
              capabilities=$(cut -d= -f2- <<<"$capabilities")
              case ":$capabilities:" in
                *:capture:*) ;;
                *) continue ;;
              esac
              printf '%s\n' "$node"
              return 0
            done
            return 1
          }

          # The preview is drawn on a headless (no physical display attached)
          # output, so the window exists for the screen-share picker without
          # ever appearing on a monitor. Creating it here rather than in the
          # Hyprland config is what keeps the launch safe: if the output is
          # missing the preview is not started at all, so it can never fall
          # back onto a physical display.
          ensure_output() {
            local want have
            if ! hyprctl monitors 2>/dev/null | grep -q "^Monitor $output_name "; then
              echo "creating headless output $output_name"
              hyprctl output create headless "$output_name" >/dev/null 2>&1 || return 1
            fi
            # A newly created headless output comes up on a small default mode,
            # and the monitor entry in the Hyprland config only applies on a
            # config reload, which happens before this service creates the
            # output. Without setting the mode here, every fresh boot leaves a
            # half resolution share source with the fullscreen window cropped
            # to its top left corner.
            hyprctl eval "hl.monitor({ output = '$output_name', mode = '$output_mode', scale = $output_scale })" >/dev/null 2>&1
            # hyprctl reports the mode as "<width>x<height>@<refresh>", so
            # compare the resolution only and let the refresh rate vary.
            want=$(cut -d@ -f1 <<<"$output_mode")
            have=$(hyprctl monitors 2>/dev/null | grep -A1 "^Monitor $output_name " | tail -1 | tr -s '[:space:]' ' ' | cut -d' ' -f2 | cut -d@ -f1)
            if [[ $have != "$want" ]]; then
              echo "warning: headless output $output_name is $have, expected $want"
              return 1
            fi
          }

          wait_for_compositor() {
            local attempt
            for ((attempt = 0; attempt < 60; attempt++)); do
              hyprctl monitors >/dev/null 2>&1 && return 0
              sleep 1
            done
            return 1
          }

          start_preview() {
            local node=$1
            echo "starting capture preview on $node"
            # No --fs and no --fs-screen: mpv 0.41 only accepts a monitor
            # index for --fs-screen, and that index does not follow the order
            # hyprctl reports. The "capture-card-preview" window rule assigns
            # the headless output and fullscreen by name instead, so the
            # placement needs no index at all.
            #
            # No --demuxer-lavf-o hints either: the sc0710 driver negotiates
            # yuyv422 1080p on its own, and forcing input_format/video_size
            # makes every VIDIOC_QBUF fail.
            mpv "av://v4l2:$node" \
              --profile=low-latency \
              --untimed \
              --title="$window_title" \
              --no-border \
              --keep-open=yes \
              --osd-level=0 \
              --no-osc \
              --no-osd-bar \
              --no-input-default-bindings \
              --no-input-cursor \
              --input-conf=/dev/null &
            preview_pid=$!
          }

          stop_preview() {
            if [[ -n $preview_pid ]]; then
              echo "stopping capture preview (pid $preview_pid)"
              kill "$preview_pid" 2>/dev/null || true
              wait "$preview_pid" 2>/dev/null || true
              preview_pid=""
            fi
          }

          running() {
            [[ -n $preview_pid ]] && [[ -e /proc/$preview_pid ]]
          }

          # SIGTERM has to exit explicitly: a trap handler that only cleans up
          # would fall back into the poll loop, and systemd would then have to
          # escalate to SIGKILL on every stop.
          trap 'stop_preview; exit 0' INT TERM
          trap stop_preview EXIT

          # graphical-session.target can be reached before hyprland has created
          # its outputs, and --fs-screen is resolved once at launch.
          wait_for_compositor || echo "compositor did not answer hyprctl, continuing anyway"

          while true; do
            node=$(find_card || true)

            if [[ -z $node ]]; then
              if [[ -n $card_node ]]; then
                echo "capture card removed"
                stop_preview
                card_node=""
              fi
            elif [[ $node != "$card_node" ]] || ! running; then
              stop_preview
              if ! ensure_output; then
                echo "headless output $output_name is unavailable, not starting the preview"
                card_node=""
                sleep "$poll_interval"
                continue
              fi
              card_node=$node
              start_preview "$node"
            fi

            sleep "$poll_interval"
          done
        '';
      };
    in
    {
      options.thorn.captureCard = {
        enable = lib.mkEnableOption "fullscreen mpv preview of a PCIe capture card";

        productPattern = lib.mkOption {
          type = lib.types.str;
          default = "*Elgato 4K Pro*";
          example = "*Elgato 4K Pro*";
          description = ''
            Shell glob matched against udev's ID_V4L_PRODUCT, which is how both
            PCI and USB video nodes identify themselves. Read the real value
            with `udevadm info --query=property --name=/dev/video0` and match
            it loosely enough to survive firmware string changes.
          '';
        };

        headlessOutput = lib.mkOption {
          type = lib.types.str;
          default = "CAPTURE-OUT";
          example = "CAPTURE-OUT";
          description = ''
            Name of the headless output the preview is drawn on. The service
            creates it with `hyprctl output create headless` and never starts
            the preview without it, so the window can only ever exist on an
            output with no display attached. Must match the monitor and the
            window rule declared in the Hyprland configuration.
          '';
        };

        windowTitle = lib.mkOption {
          type = lib.types.str;
          default = "Elgato Capture Preview";
          example = "Elgato Capture Preview";
          description = ''
            Window title for the preview. mpv 0.41 has no option for the
            Wayland app id, so the title is the only handle on this window: the
            Hyprland rule that stops the preview stealing focus while gaming
            matches on it, and it keeps the window identifiable in the share
            picker.
          '';
        };

        headlessMode = lib.mkOption {
          type = lib.types.str;
          default = "1920x1080@60";
          example = "1920x1080@60";
          description = ''
            Mode set on the headless output when the preview starts. It has to
            match the size the capture card negotiates so the fullscreen window
            fills the output exactly, otherwise the shared image is cropped. The
            same mode is declared in the Hyprland monitor configuration, which
            only applies it on a config reload.
          '';
        };

        headlessScale = lib.mkOption {
          type = lib.types.int;
          default = 1;
          example = 1;
          description = ''
            Scale set on the headless output when the preview starts, applied
            together with {option}`headlessMode`.
          '';
        };

        pollIntervalSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = ''
            How often the watcher re-checks for the card. A PCIe card is
            present at boot, so this exists to cover the node appearing late
            behind driver load and disappearing again, not USB hotplug.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.user.services.elgato-capture-preview = {
          description = "Fullscreen mpv preview of the capture card, started when the card is present";
          wantedBy = [ "graphical-session.target" ];
          restartIfChanged = true;
          serviceConfig = {
            # Full path, not the bare store path: systemd execs this directly
            # and a derivation's outPath is a directory.
            ExecStart = lib.getExe preview;
            Restart = "always";
            RestartSec = "2s";
            Slice = "background.slice";
          };
        };

        # /dev/video* nodes are root-owned; uaccess is the systemd mechanism
        # that hands the seat's logged-in user an ACL on them, which is what
        # lets the preview open the card without running as root.
        services.udev.extraRules = lib.mkAfter ''
          SUBSYSTEM=="video4linux", TAG+="uaccess"
        '';
      };
    };
}
