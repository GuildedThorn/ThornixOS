{
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.programs.zellij;
    in
    {
      options.thorn.programs.zellij.enable = lib.mkEnableOption "Thorn's Zellij";

      config = lib.mkIf cfg.enable {
        programs.zellij = {
          enable = true;
          enableZshIntegration = true;
          attachExistingSession = true;

          settings = {
            simplified_ui = false;
            pane_frames = true;
            mouse_mode = false;
            scroll_buffer_size = 100000;
            default_mode = "normal";

            scrollback_editor = "nvim";
            copy_command = "wl-copy";
            copy_clipboard = "system";
            session_serialization = true;

            plugins = {
              compact-bar = {
                location = "zellij:compact-bar";
                tooltip = "Alt h";
              };
            };
          };

          layouts = {
            default = ''
              layout {
                default_tab_template {
                  children

                  pane size=1 borderless=true {
                    plugin location="zellij:compact-bar"
                  }
                }

                pane
              }
            '';

            dev = ''
              layout {
                tab name="Code" focus=true {
                  pane command="nvim"

                  pane size=1 borderless=true {
                    plugin location="zellij:compact-bar"
                  }
                }

                tab name="Files" {
                  pane command="yazi"

                  pane size=1 borderless=true {
                    plugin location="zellij:compact-bar"
                  }
                }

                tab name="Shell" {
                  pane

                  pane size=1 borderless=true {
                    plugin location="zellij:compact-bar"
                  }
                }
              }
            '';
          };
        };

        home.shellAliases = {
          zj = "zellij";
          zls = "zellij list-sessions";
          za = "zellij attach";
          zdev = "zellij attach --create dev options --default-layout dev";
        };
      };
    };
}
