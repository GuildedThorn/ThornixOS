{
  # Every keybind, isolated from the rest of the Hyprland config. Disable
  # per-host with thorn.desktop.hyprland.keybinds.enable = false (you'd
  # better have a terminal open) — or, more usefully, know that a broken
  # animation or rule elsewhere can never take the binds down with it.
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.desktop.hyprland;

      lua = lib.generators.mkLuaInline;

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
      ) (lib.range 0 8);
    in
    {
      options.thorn.desktop.hyprland.keybinds.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hyprland keybinds.";
      };

      config = lib.mkIf (cfg.enable && cfg.keybinds.enable) {
        wayland.windowManager.hyprland.settings.bind = [

          # Apps
          (bind "SUPER + RETURN" (hypr.exec "ghostty +new-window"))
          (bind "SUPER + C" (hypr.exec "gnome-calculator"))
          (bind "SUPER + B" (hypr.exec "firefox"))

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
          (bind "SUPER + S" (hypr.exec "rofi -show window"))
          (bind "SUPER + D" (hypr.exec "rofi -show drun"))
          (bind "SUPER + O" (hypr.exec "rofi -modi 'obsidian:rofi-obsidian' -show obsidian"))

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
          (bind "XF86WLAN" (hypr.exec "swayosd-client --custom-message 'WLAN Toggled'"))

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
          (bind "SUPER + L" (hypr.exec "wlogout"))
        ]
        ++ workspaceBinds;
      };
    };
}
