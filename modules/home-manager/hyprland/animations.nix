{
  # Animation curves and per-element animations, isolated from the rest of
  # the Hyprland config. If a curve or style misbehaves, set
  # thorn.desktop.hyprland.animations.enable = false on the host and rebuild
  # — keybinds, rules, and the session itself are untouched.
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.desktop.hyprland;

      lua = lib.generators.mkLuaInline;
    in
    {
      options.thorn.desktop.hyprland.animations.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hyprland animations (curves and per-element styles).";
      };

      config = lib.mkIf cfg.enable {
        wayland.windowManager.hyprland.settings = lib.mkMerge [
          {
            config.animations.enabled = cfg.animations.enable;
          }

          (lib.mkIf cfg.animations.enable {
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

              {
                # Shared shell choreography: brisk at the start, then a soft
                # settle. Hyprlock uses these same control points below.
                _args = [
                  "shell"
                  {
                    type = "bezier";
                    points = lua "{ {0.22, 1.0}, {0.36, 1.0} }";
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
                # Was a second "windows" entry (speed 5) shadowing the one
                # above — clearly meant to be the close-side counterpart of
                # windowsIn below.
                leaf = "windowsOut";
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
                leaf = "fadeDim";
                enabled = true;
                speed = 3.5;
                bezier = "shell";
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
                speed = 4;
                bezier = "shell";
                style = "fade";
              }

              {
                leaf = "layersIn";
                enabled = true;
                speed = 3.6;
                bezier = "shell";
                style = "popin 94%";
              }

              {
                leaf = "layersOut";
                enabled = true;
                speed = 2.8;
                bezier = "fast";
                style = "popin 96%";
              }

              {
                leaf = "fadeLayersIn";
                enabled = true;
                speed = 3.2;
                bezier = "shell";
              }

              {
                leaf = "fadeLayersOut";
                enabled = true;
                speed = 2.6;
                bezier = "fast";
              }

              {
                leaf = "fadeDpms";
                enabled = true;
                speed = 4;
                bezier = "shell";
              }

              {
                leaf = "specialWorkspace";
                enabled = true;
                speed = 4.5;
                bezier = "shell";
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
          })
        ];
      };
    };
}
