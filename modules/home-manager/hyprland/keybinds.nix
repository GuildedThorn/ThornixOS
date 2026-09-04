{
  # Every keybind, isolated from the rest of the Hyprland config. Disable
  # per-host with thorn.desktop.hyprland.keybinds.enable = false (you'd
  # better have a terminal open) — or, more usefully, know that a broken
  # animation or rule elsewhere can never take the binds down with it.
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.desktop.hyprland;

      lua = lib.generators.mkLuaInline;
      compactTheme = "${config.xdg.configHome}/rofi/catppuccin-command-center.rasi";

      clipboard-picker = pkgs.writeShellApplication {
        name = "clipboard-picker";
        runtimeInputs = [
          pkgs.cliphist
          pkgs.rofi
          pkgs.wl-clipboard
        ];
        text = ''
          if ! selection="$(cliphist list | rofi -theme "${compactTheme}" -dmenu -i -p "CLIPBOARD")"; then
            exit 0
          fi
          [[ -n "$selection" ]] || exit 0
          printf '%s\n' "$selection" | cliphist decode | wl-copy
        '';
      };

      calculator-picker = pkgs.writeShellApplication {
        name = "calculator-picker";
        runtimeInputs = [
          pkgs.libqalculate
          pkgs.libnotify
          pkgs.rofi
          pkgs.wl-clipboard
        ];
        text = ''
          if ! expression="$(rofi -theme "${compactTheme}" -dmenu -p "CALC" </dev/null)"; then
            exit 0
          fi
          [[ -n "$expression" ]] || exit 0

          if ! result="$(qalc -t "$expression" 2>/dev/null)"; then
            notify-send -a Thornix -u critical "Calculator" "Could not evaluate: $expression"
            exit 1
          fi

          printf '%s' "$result" | wl-copy
          notify-send -a Thornix "Calculator · copied" "$expression = $result"
        '';
      };

      emoji-picker = pkgs.writeShellApplication {
        name = "emoji-picker";
        runtimeInputs = [
          pkgs.libnotify
          pkgs.rofi
          pkgs.wl-clipboard
        ];
        text = ''
          if ! selection="$({
            printf '%s\n' \
              '😀 grin' '😂 joy' '🥹 holding back tears' '😍 heart eyes' \
              '🤔 thinking' '🫡 salute' '😎 cool' '😭 sob' '😤 triumph' \
              '🔥 fire' '✨ sparkles' '💜 purple heart' '❤️ red heart' \
              '👍 thumbs up' '👎 thumbs down' '👏 applause' '🙏 thanks' \
              '🤝 handshake' '💀 skull' '👀 eyes' '✅ done' '❌ no' \
              '⚠️ warning' '🚀 launch' '🛡️ shield' '🔒 locked' '🐧 linux' \
              '❄️ nix' '🌵 thorn' '☕ coffee' '🎉 celebrate' '🫠 melting'
          } | rofi -theme "${compactTheme}" -dmenu -i -p "EMOJI")"; then
            exit 0
          fi
          [[ -n "$selection" ]] || exit 0

          emoji="''${selection%% *}"
          printf '%s' "$emoji" | wl-copy
          notify-send -a Thornix "Emoji copied" "$emoji"
        '';
      };

      keybind-reference = pkgs.writeShellApplication {
        name = "thornix-keybinds";
        runtimeInputs = [ pkgs.rofi ];
        text = ''
          printf '%s\n' \
            'SUPER + SPACE          Command center' \
            'SUPER + /              Search this keybind reference' \
            'SUPER + RETURN         New terminal' \
            'SUPER + `              Floating scratchpad terminal' \
            'SUPER + E              Yazi file manager' \
            'SUPER + B              Firefox' \
            'SUPER + C              Calculator' \
            'SUPER + D              Applications' \
            'SUPER + S              Windows' \
            'SUPER + V              Clipboard history' \
            'SUPER + O              Obsidian search' \
            'SUPER + N              Toggle Do Not Disturb' \
            'SUPER + Q              Close focused window' \
            'SUPER + F              Fullscreen' \
            'SUPER + CTRL + F       Client fullscreen state' \
            'SUPER + G              Scroll overview' \
            'SUPER + arrows         Move focus' \
            'SUPER + SHIFT + arrows Move focused window' \
            'SUPER + CTRL + arrows  Resize focused window' \
            'SUPER + TAB            Next workspace' \
            'SUPER + SHIFT + TAB    Previous workspace' \
            'SUPER + 1…0            Focus workspace 1…10' \
            'SUPER + SHIFT + 1…0    Send window to workspace' \
            'SUPER + SHIFT + F1     Monocle layout' \
            'SUPER + SHIFT + F2     Dwindle layout' \
            'SUPER + SHIFT + F3     Scrolling layout' \
            'PRINT                  Capture active output' \
            'SUPER + PRINT          Capture window' \
            'SUPER + SHIFT + PRINT  Capture region' \
            'SUPER + CTRL + PRINT   Capture entire desktop' \
            'SUPER + CTRL + L       Lock session' \
            'SUPER + L              Power menu' \
            'Media / volume keys    SwayOSD hardware controls' \
            'XF86WLAN               ThinkPad hardware Wi-Fi toggle' \
            | rofi -theme "${compactTheme}" -dmenu -i -no-custom -p "KEYBINDS" >/dev/null || true
        '';
      };

      toggle-dnd = pkgs.writeShellApplication {
        name = "thornix-toggle-dnd";
        runtimeInputs = [
          pkgs.swayosd
          pkgs.wayle
        ];
        text = ''
          state="$(wayle notify dnd 2>&1)" || {
            swayosd-client --custom-message "Wayle notification toggle failed"
            exit 1
          }
          # An OSD remains visible even when the action just enabled DND.
          swayosd-client --custom-message "$state"
        '';
      };

      toggle-wifi = pkgs.writeShellApplication {
        name = "thornix-toggle-wifi";
        runtimeInputs = [
          pkgs.networkmanager
          pkgs.swayosd
        ];
        text = ''
          case "$(nmcli radio wifi)" in
            enabled)
              nmcli radio wifi off
              state=Off
              ;;
            disabled)
              nmcli radio wifi on
              state=On
              ;;
            *)
              swayosd-client --custom-message "Wi-Fi state unavailable"
              exit 1
              ;;
          esac

          swayosd-client --custom-message "Wi-Fi $state"
        '';
      };

      power-menu = pkgs.writeShellApplication {
        name = "thornix-power-menu";
        runtimeInputs = [
          pkgs.jq
          pkgs.wlogout
        ];
        text = ''
          width=1920
          height=1080
          geometry="$({
            hyprctl monitors -j 2>/dev/null \
              | jq -r 'first(.[] | select(.focused == true) | [((.width / .scale) | floor), ((.height / .scale) | floor)]) | @tsv'
          } 2>/dev/null || true)"

          if [[ "$geometry" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then
            read -r width height <<<"$geometry"
          fi

          margin_vertical=$((height * 31 / 100))
          margin_horizontal=$((width * 6 / 100))

          exec wlogout \
            --buttons-per-row 6 \
            --column-spacing 10 \
            --margin-top "$margin_vertical" \
            --margin-bottom "$margin_vertical" \
            --margin-left "$margin_horizontal" \
            --margin-right "$margin_horizontal"
        '';
      };

      command-center = pkgs.writeShellApplication {
        name = "thornix-command-center";
        runtimeInputs = [
          calculator-picker
          clipboard-picker
          emoji-picker
          keybind-reference
          pkgs.libnotify
          pkgs.rofi
          pkgs.systemd
          power-menu
          toggle-dnd
          toggle-wifi
        ];
        text = ''
          if ! selection="$(printf '%s\n' \
            '󰀻  Applications' \
            '󰖲  Windows' \
            '󰅇  Clipboard' \
            '󰃬  Calculator' \
            '󰞅  Emoji' \
            '󰉋  Files · Yazi' \
            '󰸉  Wallpaper · Thornix' \
            '󰆊  Wallpaper · Random' \
            '󰂚  Toggle Do Not Disturb' \
            '󰌌  Keybind reference' \
            '󰌾  Lock session' \
            '󰐥  Power menu' \
            | rofi -theme "${compactTheme}" -dmenu -i -no-custom -p "THORNIX")"; then
            exit 0
          fi

          case "$selection" in
            *Applications) rofi -show drun ;;
            *Windows) rofi -show window ;;
            *Clipboard) ${lib.getExe clipboard-picker} ;;
            *Calculator) ${lib.getExe calculator-picker} ;;
            *Emoji) ${lib.getExe emoji-picker} ;;
            *Yazi) ${lib.getExe config.programs.ghostty.package} --class=com.guildedthorn.ghostty.yazi --title=Yazi -e yazi ;;
            *Wallpaper*Thornix) wall-span thornix-obsidian-span.png ;;
            *Wallpaper*Random) wall-span ;;
            *Disturb) ${lib.getExe toggle-dnd} ;;
            *reference) ${lib.getExe keybind-reference} ;;
            *session) loginctl lock-session ;;
            *menu) ${lib.getExe power-menu} ;;
          esac
        '';
      };

      hypr = {
        exec = cmd: lua ''hl.dsp.exec_cmd("${cmd}")'';

        kill = lua "hl.dsp.window.close()";
        fullscreen = lua ''hl.dsp.window.fullscreen({ mode = "fullscreen" })'';
        fakeFullscreen = lua "hl.dsp.window.fullscreen_state({ internal = 0, client = 2, action = 'set' })";

        workspace = ws: lua ''hl.dsp.focus({ workspace = "${toString ws}" })'';
        moveToWorkspace = ws: lua ''hl.dsp.window.move({ workspace = "${toString ws}", follow = false })'';

        focus = dir: lua ''hl.dsp.focus({ direction = "${dir}" })'';
        moveWindow = dir: lua ''hl.dsp.window.move({ direction = "${dir}" })'';

        resize = x: y: lua "hl.dsp.window.resize({ x = ${x}, y = ${y}, relative = true })";

        layout =
          name:
          lua ''function() hl.exec_cmd("hyprctl eval 'hl.config({ general = { layout = \"${name}\" } })'") end'';

        scrollOverview = lua ''hl.plugin.scrolloverview.overview("toggle")'';
        scratchpad = lua ''hl.dsp.workspace.toggle_special("scratchpad")'';
      };

      bind = keys: dispatcher: {
        _args = [
          keys
          dispatcher
        ];
      };

      workspaceBinds = lib.concatMap (
        i:
        let
          ws = i + 1;
          key = "code:1${toString i}";
        in
        [
          (bind "SUPER + ${key}" (hypr.workspace ws))
          (bind "SUPER + SHIFT + ${key}" (hypr.moveToWorkspace ws))
        ]
      ) (lib.range 0 9);
    in
    {
      options.thorn.desktop.hyprland.keybinds.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hyprland keybinds.";
      };

      config = lib.mkIf (cfg.enable && cfg.keybinds.enable) {
        home.packages = [
          calculator-picker
          clipboard-picker
          command-center
          emoji-picker
          keybind-reference
          power-menu
          toggle-dnd
          # These commands are direct keybind targets and should not depend
          # on one host happening to install them at the NixOS level.
          pkgs.rofi-obsidian
          pkgs.wl-clipboard
        ];

        wayland.windowManager.hyprland.settings.bind = [

          # Apps
          (bind "SUPER + RETURN" (hypr.exec "ghostty +new-window"))
          (bind "SUPER + grave" hypr.scratchpad)
          (bind "SUPER + C" (hypr.exec "gnome-calculator"))
          (bind "SUPER + B" (hypr.exec "firefox"))
          (bind "SUPER + E" (hypr.exec "ghostty --class=com.guildedthorn.ghostty.yazi --title=Yazi -e yazi"))

          # Window actions
          (bind "SUPER + Q" hypr.kill)
          (bind "SUPER + G" hypr.scrollOverview)
          (bind "SUPER + F" hypr.fullscreen)
          (bind "SUPER + CTRL + F" hypr.fakeFullscreen)

          # Workspace navigation
          (bind "SUPER + SHIFT + Tab" (hypr.workspace "m-1"))
          (bind "SUPER + Tab" (hypr.workspace "m+1"))

          # Resize
          (bind "SUPER + CTRL + left" (hypr.resize "-20" "0"))
          (bind "SUPER + CTRL + right" (hypr.resize "20" "0"))
          (bind "SUPER + CTRL + up" (hypr.resize "0" "-20"))
          (bind "SUPER + CTRL + down" (hypr.resize "0" "20"))

          # Focus
          (bind "SUPER + left" (hypr.focus "left"))
          (bind "SUPER + right" (hypr.focus "right"))
          (bind "SUPER + up" (hypr.focus "up"))
          (bind "SUPER + down" (hypr.focus "down"))

          # Move windows
          (bind "SUPER + SHIFT + left" (hypr.moveWindow "left"))
          (bind "SUPER + SHIFT + right" (hypr.moveWindow "right"))
          (bind "SUPER + SHIFT + up" (hypr.moveWindow "up"))
          (bind "SUPER + SHIFT + down" (hypr.moveWindow "down"))

          # Rofi
          (bind "SUPER + SPACE" (hypr.exec (lib.getExe command-center)))
          (bind "SUPER + slash" (hypr.exec (lib.getExe keybind-reference)))
          (bind "SUPER + S" (hypr.exec "rofi -show window"))
          (bind "SUPER + D" (hypr.exec "rofi -show drun"))
          (bind "SUPER + O" (hypr.exec "rofi -modi 'obsidian:rofi-obsidian' -show obsidian"))
          (bind "SUPER + V" (hypr.exec (lib.getExe clipboard-picker)))
          (bind "SUPER + N" (hypr.exec (lib.getExe toggle-dnd)))

          # Layouts
          (bind "SUPER + SHIFT + F1" (hypr.layout "monocle"))
          (bind "SUPER + SHIFT + F2" (hypr.layout "dwindle"))
          (bind "SUPER + SHIFT + F3" (hypr.layout "scrolling"))

          # Brightness
          (bind "XF86MonBrightnessUp" (hypr.exec "swayosd-client --brightness raise"))

          (bind "XF86MonBrightnessDown" (hypr.exec "swayosd-client --brightness lower"))

          # Media
          (bind "XF86AudioPlay" (hypr.exec "swayosd-client --playerctl play-pause"))

          (bind "XF86AudioNext" (hypr.exec "swayosd-client --playerctl next"))

          (bind "XF86AudioPrev" (hypr.exec "swayosd-client --playerctl previous"))

          # Volume
          (bind "XF86AudioMute" (hypr.exec "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))

          (bind "XF86AudioMicMute" (hypr.exec "wpctl set-mute @DEFAULT_SOURCE@ toggle"))
          (bind "XF86AudioRaiseVolume" (hypr.exec "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"))
          (bind "XF86AudioLowerVolume" (hypr.exec "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"))

          # Misc
          (bind "XF86WLAN" (hypr.exec (lib.getExe toggle-wifi)))

          (bind "XF86Calculator" (hypr.exec "gnome-calculator"))
          (bind "XF86Display" (hypr.exec "nwg-displays"))

          # Screenshots
          (bind "PRINT" (hypr.exec "hyprshot -m output -o /home/thorn/Pictures/screenshots"))

          # Full desktop, all three monitors as one strip (grim with no
          # output argument captures the whole layout)
          (bind "SUPER + CTRL + PRINT" (
            hypr.exec "grim /home/thorn/Pictures/screenshots/desktop-$(date +%Y%m%d-%H%M%S).png"
          ))

          (bind "SUPER + PRINT" (hypr.exec "hyprshot -m window -c -o /home/thorn/Pictures/screenshots"))

          (bind "SUPER + SHIFT + PRINT" (hypr.exec "hyprshot -m region -o /home/thorn/Pictures/screenshots"))

          # Logout
          (bind "SUPER + CTRL + L" (hypr.exec "loginctl lock-session"))
          (bind "SUPER + L" (hypr.exec (lib.getExe power-menu)))
        ]
        ++ workspaceBinds;
      };
    };
}
