{
  # Window rules (workspace assignment, screenshare protection), isolated so
  # a bad match regex can be disabled per-host without touching anything else:
  # thorn.desktop.hyprland.windowRules.enable = false.
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.desktop.hyprland;
      scratchpadClass = "com.guildedthorn.ghostty.scratchpad";
      rice = import ../../../lib/rice.nix;
      inherit (rice) colors;
    in
    {
      options.thorn.desktop.hyprland.windowRules.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hyprland window rules.";
      };

      config = lib.mkIf (cfg.enable && cfg.windowRules.enable) {
        wayland.windowManager.hyprland.settings = {
          # Toggling an empty special workspace launches its terminal. Closing
          # the terminal destroys it; the next toggle creates a fresh one.
          workspace_rule = [
            {
              workspace = "special:scratchpad";
              on_created_empty = "${lib.getExe config.programs.ghostty.package} --class=${scratchpadClass} --title=Scratchpad";
            }
            {
              # No dead frame around a lone tiled window; explicitly exclude
              # special workspaces so the floating scratchpad keeps its stage.
              workspace = "w[tv1]s[false]";
              gaps_in = 0;
              gaps_out = 0;
            }
            {
              workspace = "f[1]s[false]";
              gaps_in = 0;
              gaps_out = 0;
            }
          ];

          window_rule = [
            {
              name = "smart-single-border";
              border_size = 0;
              match = {
                float = false;
                workspace = "w[tv1]s[false]";
              };
            }

            {
              name = "smart-single-rounding";
              rounding = 0;
              match = {
                float = false;
                workspace = "w[tv1]s[false]";
              };
            }

            {
              name = "smart-fullscreen-border";
              border_size = 0;
              match = {
                float = false;
                workspace = "f[1]s[false]";
              };
            }

            {
              name = "smart-fullscreen-rounding";
              rounding = 0;
              match = {
                float = false;
                workspace = "f[1]s[false]";
              };
            }

            {
              name = "noscreenshare";
              no_screen_share = 1;
              match.class = "^(?i)(.*keepassxc.*)$";
            }

            {
              name = "scratchpad-terminal";
              float = true;
              center = true;
              dim_around = true;
              animation = "popin 92%";
              border_color = {
                colors = [
                  "rgba(${colors.mauve}ff)"
                  "rgba(${colors.lavender}ff)"
                  "rgba(${colors.blue}ff)"
                ];
                angle = 45;
              };
              size = [
                "monitor_w * 0.72"
                "monitor_h * 0.68"
              ];
              match.class = "^${lib.escapeRegex scratchpadClass}$";
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
              match.class = "^(irssi|signal|Signal|org\\.telegram\\.desktop|TelegramDesktop)$";
            }

            {
              workspace = "5";
              match.class = "^(code|Code|codium|Codium|code-url-handler|obsidian|Obsidian|jetbrains-.+|jetbrains-idea|jetbrains-pycharm|jetbrains-webstorm)$";
            }
          ];

          # Layer-shell surfaces share one motion vocabulary while retaining
          # directional cues: top-edge shell chrome drops in, right-edge
          # notifications arrive laterally, and modal launchers settle at the
          # center. These namespaces are fixed by the pinned Wayle/wlogout
          # versions rather than broad guesses that could catch overlays such
          # as screenshot selectors.
          layer_rule = [
            {
              name = "wayle-bars";
              blur = true;
              blur_popups = true;
              ignore_alpha = 0.14;
              animation = "slide top";
              match.namespace = "^wayle-bar-.*$";
            }
            {
              name = "wayle-notifications";
              blur = true;
              ignore_alpha = 0.14;
              animation = "slide right";
              match.namespace = "^wayle-notification-popup$";
            }
            {
              name = "wayle-osd";
              blur = true;
              ignore_alpha = 0.14;
              animation = "popin 88%";
              match.namespace = "^wayle-osd$";
            }
            {
              name = "swayosd";
              blur = true;
              ignore_alpha = 0.14;
              animation = "popin 88%";
              match.namespace = "^swayosd.*$";
            }
            {
              name = "rofi-command-surfaces";
              blur = true;
              ignore_alpha = 0.12;
              dim_around = true;
              animation = "popin 92%";
              match.namespace = "^rofi$";
            }
            {
              name = "wlogout-overlay";
              blur = true;
              ignore_alpha = 0.1;
              dim_around = true;
              animation = "fade";
              match.namespace = "^wlogout$";
            }
          ];
        };
      };
    };
}
