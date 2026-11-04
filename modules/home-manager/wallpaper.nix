{ inputs, ... }:
{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.desktop.wallpaper;

      awww = inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww;
      hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

      # Slices one wallpaper across every active monitor using the real layout
      # coordinates from hyprctl, so the desktop reads as one continuous image
      # (monitor gaps included). Each slice is pushed to awww with an animated
      # transition. Run with no args for a random pick, or pass a filename.
      wall-span = pkgs.writeShellApplication {
        name = "wall-span";
        runtimeInputs = [
          awww
          hyprland
          pkgs.imagemagick
          pkgs.jq
          pkgs.findutils
          pkgs.coreutils
        ];
        text = ''
          WALL_DIR="''${WALL_DIR:-${cfg.directory}}"
          CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/wall-span"
          mkdir -p "$CACHE_DIR"

          if [ $# -ge 1 ]; then
            img="$1"
            [ -f "$img" ] || img="$WALL_DIR/$1"
          else
            img=$(find "$WALL_DIR" -maxdepth 1 -type f \
              \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | shuf -n 1)
          fi
          [ -f "$img" ] || { echo "wallpaper not found: $img" >&2; exit 1; }

          # awww-daemon is started by hyprland; wait for it after login
          for _ in $(seq 1 50); do
            awww query >/dev/null 2>&1 && break
            sleep 0.2
          done

          # logical geometry of every active monitor (handles scale and rotation)
          mons=$(hyprctl monitors -j | jq -c '[.[] | select(.disabled | not) | {
            name,
            x,
            y,
            fps: (.refreshRate | round),
            w: (if (.transform % 2) == 1 then (.height / .scale | round) else (.width / .scale | round) end),
            h: (if (.transform % 2) == 1 then (.width / .scale | round) else (.height / .scale | round) end)
          }]')

          minx=$(jq -r 'map(.x) | min' <<<"$mons")
          miny=$(jq -r 'map(.y) | min' <<<"$mons")
          maxx=$(jq -r 'map(.x + .w) | max' <<<"$mons")
          maxy=$(jq -r 'map(.y + .h) | max' <<<"$mons")
          bw=$((maxx - minx))
          bh=$((maxy - miny))

          # one canvas covering the whole layout, then a slice per monitor
          canvas="$CACHE_DIR/canvas.png"
          magick "$img" -resize "''${bw}x''${bh}^" -gravity center -extent "''${bw}x''${bh}" "$canvas"

          while IFS= read -r mon; do
            name=$(jq -r .name <<<"$mon")
            x=$(jq -r .x <<<"$mon")
            y=$(jq -r .y <<<"$mon")
            w=$(jq -r .w <<<"$mon")
            h=$(jq -r .h <<<"$mon")
            fps=$(jq -r .fps <<<"$mon")
            slice="$CACHE_DIR/$name.png"
            magick "$canvas" -crop "''${w}x''${h}+$((x - minx))+$((y - miny))" +repage "$slice"
            awww img --outputs "$name" "$slice" --resize crop \
              --transition-type ${cfg.transition} --transition-angle 30 \
              --transition-duration 2 --transition-fps "$fps" &
          done < <(jq -c '.[]' <<<"$mons")
          wait
        '';
      };
    in
    {
      options.thorn.desktop.wallpaper = {
        enable = lib.mkEnableOption "wallpaper spanning all monitors as one screen, rotated with animated transitions";

        featured = lib.mkOption {
          type = lib.types.path;
          default = ../../assets/wallpapers/thornix-obsidian-span.png;
          description = "Wallpaper shown when the graphical session starts before normal rotation begins.";
        };

        directory = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/Pictures/walls-catppuccin-mocha";
          description = "Directory of wallpapers to pick from.";
        };

        interval = lib.mkOption {
          type = lib.types.str;
          default = "15min";
          description = "How often to rotate to a new random wallpaper (systemd time span).";
        };

        transition = lib.mkOption {
          type = lib.types.str;
          default = "wipe";
          description = "awww transition type used when the wallpaper changes.";
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ wall-span ];

        # Keep the project artwork available alongside personal wallpapers so
        # `wall-span thornix-obsidian-span.png` can always restore the intended
        # screenshot composition without referring to a Nix store path.
        home.file."Pictures/walls-catppuccin-mocha/thornix-obsidian-span.png".source = cfg.featured;

        systemd.user.services.wall-span-featured = {
          Unit = {
            Description = "Set the featured ThornixOS spanning wallpaper";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${lib.getExe wall-span} ${lib.escapeShellArg (toString cfg.featured)}";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        systemd.user.services.wall-span = {
          Unit = {
            Description = "Spanning wallpaper across all monitors";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe wall-span;
          };
        };

        systemd.user.timers.wall-span = {
          Unit.Description = "Rotate spanning wallpaper";
          Timer = {
            OnActiveSec = cfg.interval;
            OnUnitActiveSec = cfg.interval;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
