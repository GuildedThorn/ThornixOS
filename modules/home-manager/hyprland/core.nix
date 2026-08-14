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
      rice = import ../../../lib/rice.nix;
      inherit (rice) colors fonts geometry;
      thornixMarkPng = rice.branding.png pkgs 192;

      lockStatus = pkgs.writeShellApplication {
        name = "hyprlock-status";
        runtimeInputs = [ pkgs.playerctl ];
        text = ''
          for supply in /sys/class/power_supply/BAT*; do
            [ -d "$supply" ] || continue
            [ -r "$supply/capacity" ] || continue

            read -r capacity < "$supply/capacity"
            status="Unknown"
            [ ! -r "$supply/status" ] || read -r status < "$supply/status"
            printf 'Battery %s%% · %s\n' "$capacity" "$status"
            break
          done

          metadata=$(playerctl metadata --format '{{title}} — {{artist}}' 2>/dev/null || true)
          if [ -n "$metadata" ]; then
            printf 'Now playing · %.88s\n' "$metadata"
          fi
        '';
      };

      wlogoutIcon = label: "${pkgs.wlogout}/share/wlogout/icons/${label}.png";
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
              background-opacity = 84;
              border-color = "border-strong";
              border-location = "all";
              border-width = geometry.border;
              inset-edge = 0.75;
              inset-ends = 1.25;
              module-gap = 0.65;
              padding = 0.45;
              padding-ends = 1.2;
              rounding = "lg";
              scale = 0.85;
              shadow = "floating";
              button-variant = "block-prefix";
              button-bg-opacity = 74;
              button-rounding = "md";
              button-gap = 0.65;
              button-group-background = "bg-elevated";
              button-group-opacity = 78;
              button-group-padding = 0.2;
              button-group-module-gap = 0.35;
              button-group-rounding = "md";
              dropdown-opacity = 94;
              dropdown-shadow = true;
            };
            general = {
              font-sans = fonts.sans;
              font-mono = fonts.mono;
            };
            modules = {
              custom = [
                {
                  id = "thornix";
                  command = "printf THORNIX";
                  interval-ms = 0;
                  format = "{{ output }}";
                  tooltip-format = "SUPER + SPACE  ·  command center\nRight click  ·  session menu";
                  class-format = "thornix-brand";
                  icon-show = false;
                  label-color = "accent";
                  button-bg-color = "bg-surface-elevated";
                  border-show = true;
                  border-color = "accent";
                  left-click = "thornix-command-center";
                  right-click = "thornix-power-menu";
                }
              ];
              clock = {
                dropdown-show-seconds = true;
                format = "%a %b %d %H:%M";
              };
              cava = {
                bars = 14;
                bar-width = 5;
                bar-gap = 2;
                color = "accent";
              };
              cpu = {
                left-click = "ghostty -e btop";
              };
              hyprland-workspaces = {
                min-workspace-count = 5;
                monitor-specific = false;
                show-special = true;
                urgent-show = true;
                urgent-mode = "application";
                display-mode = "icon";
                divider = "·";
                app-icons-show = true;
                app-icons-dedupe = true;
                app-icons-empty = "tb-minus-symbolic";
                icon-gap = 0.25;
                workspace-padding = 0.45;
                icon-size = 0.95;
                label-size = 0.9;
                active-indicator = "underline";
                active-color = "accent";
                occupied-color = "fg-muted";
                empty-color = "fg-subtle";
                workspace-map = {
                  "1".icon = "ld-headphones-symbolic";
                  "2".icon = "ld-terminal-symbolic";
                  "3".icon = "ld-globe-symbolic";
                  "4".icon = "ld-message-circle-symbolic";
                  "5".icon = "ld-code-symbolic";
                  "-99".icon = "ld-layers-symbolic";
                };
                app-icon-map = {
                  "class:com.guildedthorn.ghostty.scratchpad" = "ld-terminal-symbolic";
                  "class:com.guildedthorn.ghostty.yazi" = "ld-folder-open-symbolic";
                };
              };
              notifications = {
                border-show = true;
                border-color = "accent";
                icon-color = "auto";
                icon-bg-color = "accent";
                label-show = true;
                label-color = "accent";
                button-bg-color = "bg-surface-elevated";
                right-click = "wayle notify dnd";
                middle-click = "wayle notify dismiss-all";
                popup-position = "top-right";
                popup-max-visible = 3;
                popup-stacking-order = "newest-first";
                popup-duration = 5500;
                popup-hover-pause = true;
                # Visually clears the floating bar before the first card and
                # keeps the card edge aligned with the bar's right inset.
                popup-margin-x = 1.25;
                popup-margin-y = 4.25;
                popup-gap = 0.75;
                popup-close-behavior = "dismiss";
                popup-shadow = true;
                popup-urgency-bar = "low";
                thresholds = [
                  {
                    above = 5;
                    icon-color = "status-warning";
                    label-color = "status-warning";
                    border-color = "status-warning";
                  }
                  {
                    above = 12;
                    icon-color = "status-error";
                    label-color = "status-error";
                    border-color = "status-error";
                  }
                ];
              };
              weather = {
                location = "Alsip";
              };
              window-title = {
                format = "{{ title }}";
                label-max-length = 42;
                icon-bg-color = "blue";
                label-color = "fg-muted";
              };
            };
            styling = {
              theme-provider = "wayle";
              matugen-contrast = -1;
              pywal-saturation = 0;
              rounding = "lg";
              palette = {
                bg = "#${colors.crust}";
                surface = "#${colors.base}";
                elevated = "#${colors.surface0}";
                fg = "#${colors.text}";
                fg-muted = "#${colors.subtext0}";
                primary = "#${colors.mauve}";
                red = "#${colors.red}";
                yellow = "#${colors.yellow}";
                green = "#${colors.green}";
                blue = "#${colors.blue}";
              };
            };
            wallpaper = {
              engine-enabled = false;
            };
          };
        };
        stylix.targets.wayle.enable = false;

        # Wayle intentionally keeps normal colors/layout in config.toml. This
        # small managed override adds the interaction layer that its schema
        # cannot express while keeping the palette static and reproducible.
        xdg.configFile."wayle/styles/index.scss".text = ''
          menubutton.bar-button {
            transition: background-color 140ms ease-out,
                        color 140ms ease-out,
                        box-shadow 140ms ease-out;
          }

          menubutton.bar-button:hover {
            --bar-btn-bg: var(--palette-primary);
            --bar-btn-label-color: var(--palette-bg);
            --bar-btn-label-weight: 700;
            box-shadow: 0 4px 14px #${colors.crust}80;
          }

          menubutton.bar-button:active,
          menubutton.bar-button:checked,
          menubutton.bar-button.primary-clock {
            --bar-btn-bg: var(--palette-primary);
            --bar-btn-label-color: var(--palette-bg);
            --bar-btn-label-weight: 700;
          }

          menubutton.bar-button.thornix-brand {
            --bar-btn-label-weight: 800;
            box-shadow: inset 0 -2px 0 #${colors.mauve}cc,
                        0 4px 14px #${colors.crust}66;
          }

          menubutton.bar-button.thornix-brand label {
            font-family: "${fonts.mono}";
            font-weight: 800;
          }

          popover > contents {
            border: ${toString geometry.border}px solid #${colors.mauve}55;
            border-radius: ${toString geometry.radiusLarge}px;
            box-shadow: 0 12px 32px #${colors.crust}b3;
            transition: border-color 160ms ease-out,
                        box-shadow 160ms ease-out;
          }

          .workspace {
            transition: background-color 180ms cubic-bezier(0.22, 1, 0.36, 1),
                        box-shadow 180ms cubic-bezier(0.22, 1, 0.36, 1),
                        opacity 180ms cubic-bezier(0.22, 1, 0.36, 1);
          }

          .workspace.active {
            background-color: #${colors.mauve}1f;
            box-shadow: inset 0 -2px 0 #${colors.mauve};
          }

          .workspace.occupied:not(.active) {
            background-color: #${colors.surface1}38;
          }

          .workspace.urgent,
          .workspace-icon.urgent {
            box-shadow: 0 0 12px #${colors.red}99;
          }

          .workspace-label,
          .workspace-icon,
          .workspace-custom-icon,
          .workspace-divider {
            transition: color 180ms cubic-bezier(0.22, 1, 0.36, 1),
                        opacity 180ms cubic-bezier(0.22, 1, 0.36, 1);
          }

          .notification-popup-list {
            margin: 0;
          }

          .notification-popup-card {
            border: ${toString geometry.border}px solid #${colors.mauve}55;
            border-radius: ${toString geometry.radiusLarge}px;
            box-shadow: 0 12px 32px #${colors.crust}b3;
            transition: border-color 160ms ease-out,
                        box-shadow 160ms ease-out;
          }

          .notification-popup-card:hover {
            border-color: #${colors.lavender}aa;
            box-shadow: 0 16px 38px #${colors.crust}cc;
          }

          .notification-popup-card.critical {
            border-color: #${colors.red}aa;
          }

          .notification-popup-card.low {
            border-color: #${colors.overlay0}66;
          }

          .notification-dropdown-dnd-row {
            border: 1px solid #${colors.mauve}55;
          }

          .notification-dropdown-dnd-row switch:checked {
            background-color: #${colors.mauve};
            color: #${colors.crust};
          }

          tooltip.background {
            border: 1px solid #${colors.overlay0}99;
            border-radius: ${toString geometry.radiusSmall}px;
          }
        '';

        # NixOS supplies the binaries and Hyprlock PAM service. Home Manager
        # owns their user-facing configuration so the system-wide Hypridle
        # unit has a real policy to load instead of crash-looping.
        programs.hyprlock = {
          enable = true;
          package = null;
          settings = {
            general = {
              hide_cursor = true;
              ignore_empty_input = true;
            };

            animations = {
              enabled = true;
              bezier = [ "shell, 0.22, 1.0, 0.36, 1.0" ];
              animation = [
                "fadeIn, 1, 4, shell"
                "fadeOut, 1, 3, shell"
                "inputFieldDots, 1, 2, shell"
              ];
            };

            # Attribute sets (rather than one-element lists) merge cleanly
            # with Stylix's generated Catppuccin colors for these blocks.
            background = {
              monitor = "";
              path = "screenshot";
              blur_passes = 3;
              blur_size = 8;
              color = "rgb(${colors.base})";
            };

            image = {
              monitor = "";
              path = "${thornixMarkPng}";
              size = 92;
              position = "0, 285";
              halign = "center";
              valign = "center";
              border_size = 0;
              rounding = -1;
              shadow_passes = 3;
              shadow_size = 7;
              shadow_color = "rgba(${colors.crust}b3)";
            };

            input-field = {
              monitor = "";
              size = "340, 58";
              position = "0, -105";
              dots_center = true;
              fade_on_empty = false;
              font_color = "rgb(${colors.text})";
              inner_color = "rgba(${colors.base}e6)";
              outer_color = "rgba(${colors.mauve}cc)";
              check_color = "rgb(${colors.green})";
              fail_color = "rgb(${colors.red})";
              outline_thickness = geometry.border;
              rounding = geometry.radiusMedium;
              placeholder_text = ''<span foreground="##${colors.subtext0}">Password...</span>'';
              shadow_passes = 3;
              shadow_size = 6;
              shadow_color = "rgba(${colors.crust}b3)";
            };

            label = [
              {
                monitor = "";
                text = "THORNIX  //  SECURE SESSION";
                color = "rgb(${colors.mauve})";
                font_family = fonts.mono;
                font_size = 14;
                position = "0, 225";
                halign = "center";
                valign = "center";
                shadow_passes = 2;
                shadow_size = 3;
                shadow_color = "rgba(${colors.crust}b3)";
              }
              {
                monitor = "";
                text = "$TIME";
                color = "rgb(${colors.text})";
                font_family = fonts.sans;
                font_size = 72;
                position = "0, 170";
                halign = "center";
                valign = "center";
                shadow_passes = 3;
                shadow_size = 4;
                shadow_color = "rgba(${colors.crust}b3)";
              }
              {
                monitor = "";
                text = "cmd[update:60000] date '+%A, %B %d'";
                color = "rgb(${colors.subtext1})";
                font_family = fonts.sans;
                font_size = 18;
                position = "0, 110";
                halign = "center";
                valign = "center";
                shadow_passes = 2;
                shadow_size = 3;
                shadow_color = "rgba(${colors.crust}b3)";
              }
              {
                monitor = "";
                text = "Welcome back, $USER";
                color = "rgb(${colors.mauve})";
                font_family = fonts.sans;
                font_size = 16;
                position = "0, -42";
                halign = "center";
                valign = "center";
                shadow_passes = 2;
                shadow_size = 3;
                shadow_color = "rgba(${colors.crust}b3)";
              }
              {
                monitor = "";
                text = "cmd[update:10000] ${lib.getExe lockStatus}";
                color = "rgb(${colors.subtext0})";
                font_family = fonts.mono;
                font_size = 13;
                position = "0, -175";
                halign = "center";
                valign = "center";
                shadow_passes = 2;
                shadow_size = 3;
                shadow_color = "rgba(${colors.crust}b3)";
              }
            ];
          };
        };
        stylix.targets.hyprlock.enable = false;

        services.hypridle = {
          enable = true;
          # The NixOS module already installs and starts Hypridle. A null HM
          # package generates only ~/.config/hypr/hypridle.conf, avoiding a
          # second user-unit definition for the same daemon.
          package = null;
          settings = {
            general = {
              lock_cmd = "pidof hyprlock || hyprlock";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl dispatch dpms on";
              ignore_dbus_inhibit = false;
            };

            listener = [
              {
                timeout = 600;
                on-timeout = "loginctl lock-session";
              }
              {
                timeout = 900;
                on-timeout = "hyprctl dispatch dpms off";
                on-resume = "hyprctl dispatch dpms on";
              }
            ];
          };
        };

        # security.polkit enables the authority; this is the session agent
        # that can actually present authentication prompts under Hyprland.
        services.hyprpolkitagent.enable = true;

        programs.wlogout = {
          enable = true;

          style = ''
            * {
              background-image: none;
              box-shadow: none;
              font-family: "${fonts.sans}";
              font-size: 16px;
            }

            window {
              background-color: rgba(17, 17, 27, 0.78);
              background-image: image(url("${thornixMarkPng}"), transparent);
              background-repeat: no-repeat;
              background-position: center 14%;
              background-size: 116px;
            }

            button {
              color: #${colors.text};
              background-color: rgba(30, 30, 46, 0.82);
              border: ${toString geometry.border}px solid rgba(108, 112, 134, 0.52);
              border-radius: ${toString geometry.radiusLarge}px;
              margin: 7px;
              box-shadow: 0 12px 32px rgba(17, 17, 27, 0.65);
              background-repeat: no-repeat;
              background-position: center;
              background-size: 56px;
              outline-style: none;
              transition: background-color 160ms ease-out,
                          border-color 160ms ease-out,
                          box-shadow 160ms ease-out;
            }

            button:focus,
            button:active,
            button:hover {
              color: #${colors.crust};
              background-color: rgba(203, 166, 247, 0.92);
              border-color: #${colors.lavender};
              box-shadow: 0 16px 40px rgba(17, 17, 27, 0.78);
            }

            #shutdown:focus,
            #shutdown:active,
            #shutdown:hover {
              background-color: rgba(243, 139, 168, 0.94);
              border-color: #${colors.red};
            }

            #logout:focus,
            #logout:active,
            #logout:hover {
              background-color: rgba(250, 179, 135, 0.94);
              border-color: #${colors.peach};
            }

            #suspend:focus,
            #suspend:active,
            #suspend:hover,
            #hibernate:focus,
            #hibernate:active,
            #hibernate:hover {
              background-color: rgba(137, 180, 250, 0.94);
              border-color: #${colors.blue};
            }

            #reboot:focus,
            #reboot:active,
            #reboot:hover {
              background-color: rgba(249, 226, 175, 0.94);
              border-color: #${colors.yellow};
            }

            #lock { background-image: image(url("${wlogoutIcon "lock"}")); }
            #hibernate { background-image: image(url("${wlogoutIcon "hibernate"}")); }
            #logout { background-image: image(url("${wlogoutIcon "logout"}")); }
            #shutdown { background-image: image(url("${wlogoutIcon "shutdown"}")); }
            #suspend { background-image: image(url("${wlogoutIcon "suspend"}")); }
            #reboot { background-image: image(url("${wlogoutIcon "reboot"}")); }
          '';

          layout = [
            {
              label = "lock";
              action = "${pkgs.hyprlock}/bin/hyprlock";
              text = "LOCK  ·  L";
              keybind = "l";
            }
            {
              label = "suspend";
              action = "systemctl suspend";
              text = "SUSPEND  ·  U";
              keybind = "u";
            }
            {
              label = "hibernate";
              action = "systemctl hibernate";
              text = "HIBERNATE  ·  H";
              keybind = "h";
            }
            {
              label = "logout";
              action = "${
                inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland
              }/bin/hyprctl dispatch exit";
              text = "LOGOUT  ·  E";
              keybind = "e";
            }
            {
              label = "reboot";
              action = "systemctl reboot";
              text = "REBOOT  ·  R";
              keybind = "r";
            }
            {
              label = "shutdown";
              action = "systemctl poweroff";
              text = "SHUTDOWN  ·  S";
              keybind = "s";
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

                "col.active_border" = lib.mkForce {
                  colors = [
                    "rgba(${colors.mauve}ff)"
                    "rgba(${colors.lavender}ff)"
                  ];
                  angle = 45;
                };
                "col.inactive_border" = lib.mkForce "rgba(${colors.surface1}99)";

                resize_on_border = true;
                allow_tearing = false;
                layout = "dwindle";
              };

              group = {
                "col.border_active" = lib.mkForce {
                  colors = [
                    "rgba(${colors.mauve}ff)"
                    "rgba(${colors.lavender}ff)"
                  ];
                  angle = 45;
                };
                "col.border_inactive" = lib.mkForce "rgba(${colors.surface1}99)";
                groupbar = {
                  "col.active" = lib.mkForce "rgba(${colors.mauve}ff)";
                  "col.inactive" = lib.mkForce "rgba(${colors.surface1}cc)";
                  text_color = lib.mkForce "rgba(${colors.text}ff)";
                };
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
                rounding = geometry.radiusMedium;
                dim_inactive = true;
                dim_strength = 0.055;
                dim_special = 0.18;
                dim_around = 0.22;

                blur = {
                  enabled = true;
                  size = 6;
                  passes = 2;
                  special = true;
                  popups = true;
                  popups_ignorealpha = 0.2;
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
