{ inputs, ... }:
{
  # Base Hyprland session: compositor, companion services, and the settings
  # that rarely break. The riskier, hand-tuned concerns live in sibling files
  # (animations.nix, keybinds.nix, window-rules.nix), each behind its own
  # enable flag — a misbehaving animation config can be switched off without
  # touching keybinds, and vice versa.
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
    in
    {
      options.thorn.desktop.hyprland.enable = lib.mkEnableOption "Hyprland Home Manager configuration";

      config = lib.mkIf cfg.enable {
        home.packages = with pkgs; [
          gnome-calculator
          grim
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
              action = "${
                inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland
              }/bin/hyprctl dispatch exit";
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
            # Passed as an explicit path (not the bare package) because home-manager
            # derives the .so name from the package's `pname` ("hyprland-scroll-overview"),
            # but this plugin's build output is actually named libscrolloverview.so.
            "${
              inputs.hyprland-scroll-overview.packages.${pkgs.stdenv.hostPlatform.system}.default
            }/lib/libscrolloverview.so"
          ];

          settings = {
            #################################
            # Autostart
            #################################

            on = {
              _args = [
                "hyprland.start"
                # The swayosd libinput backend is a system service now (see
                # modules/desktop/hyprland.nix) — no pkexec prompt at login.
                (lua ''
                  function()
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

              misc = {
                disable_hyprland_logo = true;
                disable_splash_rendering = true;
                focus_on_activate = true;
                vrr = 1;
              };
            };
          };
        };

        services.cliphist.enable = true;
        services.swayosd.enable = true;
      };
    };
}
