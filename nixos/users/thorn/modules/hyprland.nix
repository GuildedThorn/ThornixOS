{
  config,
  lib,
  pkgs,
  inputs,
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
  options.thorn.desktop.hyprland.enable = lib.mkEnableOption "Hyprland Home Manager configuration";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      gnome-calculator
    ];

    programs.hyprshot = {
      enable = true;
      saveLocation = "/home/thorn/Pictures/screenshots";
    };

    services.wayle = {
      enable = true;

      settings = {
        bar = {
          bg = "bg-surface-elevated";
          border-color = "border-strong";
          border-location = "all";
          border-width = 4;
          inset-edge = 1;
          inset-ends = 3;
          module-gap = 1;
          padding = 0.5;
          padding-ends = 1.6;
          rounding = "md";
          scale = 0.85;
          shadow = "floating";
        };
        general = {
          font-sans = "Geist";
        };
        inset-edge = 0.5;
        inset-ends = 0.5;
        modules = {
          clock = {
            dropdown-show-seconds = true;
            format = "%a %b %d %H:%M";
          };
          cpu = {
            left-click = "ghostty -e btop";
          };
          weather = {
            location = "Alsip";
          };
        };
        styling = {
          matugen-contrast = -1;
          pywal-saturation = 0;
          rounding = "lg";
        };
        wallpaper = {
          engine-enabled = false;
          monitors = [
            {
              fit-mode = "fill";
              name = "";
              wallpaper = "";
            }
          ];
        };
      };
    };

    programs.wlogout = {
      enable = true;
      layout = [
        {
          label = "lock";
          action = "${pkgs.hyprlock}/bin/hyprlock";
          text = "Lock";
          keybind = "l";
        }
        {
          label = "hibernate";
          action = "systemctl hibernate";
          text = "Hibernate";
          keybind = "h";
        }
        {
          label = "logout";
          action = "${pkgs.hyprland}/bin/hyprctl dispatch exit";
          text = "Logout";
          keybind = "e";
        }
        {
          label = "shutdown";
          action = "systemctl poweroff";
          text = "Shutdown";
          keybind = "s";
        }
        {
          label = "suspend";
          action = "systemctl suspend";
          text = "Suspend";
          keybind = "u";
        }
        {
          label = "reboot";
          action = "systemctl reboot";
          text = "Reboot";
          keybind = "r";
        }
      ];
    };

    services.mako = {
      enable = false;
      settings = {
        border-size = 2;
        border-radius = 8;
        default-timeout = 5000;
        padding = "12,20";
        margin = "10";
        icons = true;
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      configType = "lua";

      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

      plugins = [
        # inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.hyprbars
        # inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.hyprexpo
      ];

      settings = {
        #################################
        # Autostart
        #################################

        on = {
          _args = [
            "hyprland.start"
            (lua ''
              function()
                hl.exec_cmd("pkexec swayosd-libinput-backend")
                hl.exec_cmd("awww-daemon")
              end
            '')
          ];
        };

        #################################
        # General
        #################################

        config = {
          general = {
            gaps_in = 6;
            gaps_out = 10;
            border_size = 2;

            resize_on_border = true;
            allow_tearing = false;
            layout = "dwindle";
          };

          input = {
            follow_mouse = 0;
            sensitivity = 0.5;
            repeat_rate = 35;
            repeat_delay = 250;

            touchpad = {
              natural_scroll = false;
            };
          };

          dwindle = {
            preserve_split = true;
            smart_split = false;
            smart_resizing = true;
          };

          decoration = {
            rounding = 12;

            blur = {
              enabled = true;
              size = 6;
              passes = 2;
            };

            shadow = {
              enabled = true;
              range = 16;
              render_power = 3;
            };
          };

          animations = {
            enabled = true;
          };

          misc = {
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            focus_on_activate = true;
            vrr = 1;
          };
        };

        #################################
        # Animation Curves
        #################################

        curve = [
          {
            _args = [
              "smooth"
              {
                type = "bezier";
                points = lua "{ {0.25, 0.1}, {0.25, 1.0} }";
              }
            ];
          }

          {
            _args = [
              "overshot"
              {
                type = "bezier";
                points = lua "{ {0.18, 0.88}, {0.22, 1.03} }";
              }
            ];
          }

          {
            _args = [
              "fast"
              {
                type = "bezier";
                points = lua "{ {0.2, 0.75}, {0.25, 1.0} }";
              }
            ];
          }

          {
            _args = [
              "gentle"
              {
                type = "bezier";
                points = lua "{ {0.3, 0.15}, {0.25, 1.0} }";
              }
            ];
          }
        ];

        #################################
        # Animations
        #################################

        animation = [
          {
            leaf = "windows";
            enabled = true;
            speed = 6;
            bezier = "smooth";
            style = "slide";
          }

          {
            leaf = "windows";
            enabled = true;
            speed = 5;
            bezier = "smooth";
            style = "slide";
          }

          {
            leaf = "windowsIn";
            enabled = true;
            speed = 4;
            bezier = "overshot";
            style = "slide";
          }

          {
            leaf = "border";
            enabled = true;
            speed = 6;
            bezier = "gentle";
          }

          {
            leaf = "borderangle";
            enabled = true;
            speed = 5;
            bezier = "gentle";
          }

          {
            leaf = "fade";
            enabled = true;
            speed = 6;
            bezier = "smooth";
          }

          {
            leaf = "workspaces";
            enabled = true;
            speed = 5;
            bezier = "smooth";
            style = "slidevert";
          }

          {
            leaf = "layers";
            enabled = true;
            speed = 5;
            bezier = "gentle";
            style = "fade";
          }

          {
            leaf = "specialWorkspace";
            enabled = true;
            speed = 6;
            bezier = "overshot";
            style = "slidefadevert";
          }

          {
            leaf = "windowsMove";
            enabled = true;
            speed = 5;
            bezier = "fast";
            style = "slide";
          }
        ];

        #################################
        # Workspace Rules
        #################################

        window_rule = [
          {
            name = "noscreenshare";
            no_screen_share = 1;
            match.class = "^(?i)(.*keepassxc.*)$";
          }

          {
            workspace = "1";
            match.class = "^(vesktop|Vesktop|discord|Discord|Spotify|spotify|steam|Steam)$";
          }

          {
            workspace = "2";
            match.class = "^(ghostty|Ghostty|com\\.mitchellh\\.ghostty|kitty|Alacritty|org\\.wezfurlong\\.wezterm)$";
          }

          {
            workspace = "3";
            match.class = "^(firefox|Firefox|librewolf|LibreWolf|zen|Zen|chromium|Chromium|google-chrome|Google-chrome|brave-browser|Brave-browser)$";
          }

          {
            workspace = "4";
            match.class = "^(thunderbird|Thunderbird|org\\.mozilla\\.Thunderbird|irssi|signal|Signal|org\\.telegram\\.desktop|TelegramDesktop)$";
          }

          {
            workspace = "5";
            match.class = "^(code|Code|codium|Codium|code-url-handler|obsidian|Obsidian|jetbrains-.+|jetbrains-idea|jetbrains-pycharm|jetbrains-webstorm)$";
          }
        ];

        #################################
        # Keybinds
        #################################

        bind = [

          # Apps
          (bind "SUPER + RETURN" (hypr.exec "ghostty +new-window"))
          (bind "SUPER + C" (hypr.exec "gnome-calculator"))
          (bind "SUPER + V" (hypr.exec "thunderbird"))
          (bind "SUPER + B" (hypr.exec "firefox"))

          # Window actions
          (bind "SUPER + Q" hypr.kill)
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

          (bind "SUPER + PRINT" (hypr.exec "hyprshot -m window -c -o /home/thorn/Pictures/screenshots"))

          (bind "SUPER + SHIFT + PRINT" (hypr.exec "hyprshot -m region -o /home/thorn/Pictures/screenshots"))

          # Logout
          (bind "SUPER + L" (hypr.exec "wlogout"))
        ]
        ++ workspaceBinds;
      };
    };

    services.cliphist.enable = true;
    services.swayosd.enable = true;
  };
}
