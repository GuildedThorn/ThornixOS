{
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.desktop.rice;
      rice = import ../../lib/rice.nix;
      inherit (rice)
        colors
        fonts
        geometry
        ;
    in
    {
      options.thorn.desktop.rice.enable =
        lib.mkEnableOption "Thorn's shared desktop rice for Hyprland and xfce+i3";

      config = lib.mkIf cfg.enable {
        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            "audio/flac" = [ "mpv.desktop" ];
            "audio/mpeg" = [ "mpv.desktop" ];
            "audio/ogg" = [ "mpv.desktop" ];
            "audio/x-wav" = [ "mpv.desktop" ];
            "image/gif" = [ "feh.desktop" ];
            "image/jpeg" = [ "feh.desktop" ];
            "image/png" = [ "feh.desktop" ];
            "image/webp" = [ "feh.desktop" ];
            "inode/directory" = [ "yazi.desktop" ];
            "video/mp4" = [ "mpv.desktop" ];
            "video/webm" = [ "mpv.desktop" ];
            "video/x-matroska" = [ "mpv.desktop" ];
          };
        };

        programs.rofi = {
          enable = true;
          font = "${fonts.sans} 14";
          theme = "${config.xdg.configHome}/rofi/catppuccin-mocha.rasi";
        };

        # Preserve Rofi's useful fullscreen preview layout, but replace its
        # stock black/light-blue skin with the same layered Mocha surfaces,
        # Mauve focus state, and geometry used by the rest of the shell.
        xdg.configFile."rofi/catppuccin-mocha.rasi".text = ''
          * {
            background-color: transparent;
            text-color: #${colors.text};
            font: "${fonts.sans} 14";
          }

          window {
            fullscreen: true;
            background-color: #${colors.crust}d9;
            padding: 4em;
            children: [ wrap, listview-split ];
            spacing: 1em;
          }

          listview-split {
            orientation: horizontal;
            spacing: 1em;
            children: [ listview ];
          }

          wrap {
            expand: false;
            orientation: vertical;
            children: [ inputbar, message ];
            background-image: linear-gradient(#${colors.surface0}f2, #${colors.base}f2);
            border-color: #${colors.mauve}66;
            border: ${toString geometry.border}px;
            border-radius: ${toString geometry.radiusLarge}px;
          }

          icon-ib {
            expand: false;
            filename: "system-search";
            vertical-align: 0.5;
            horizontal-align: 0.5;
            size: 1.2em;
            text-color: #${colors.mauve};
          }

          inputbar {
            spacing: 0.75em;
            padding: 0.85em 1em;
            children: [ icon-ib, prompt, entry ];
          }

          prompt {
            text-color: #${colors.mauve};
          }

          entry {
            placeholder: "Search";
            placeholder-color: #${colors.overlay1};
            text-color: #${colors.text};
          }

          message {
            background-color: #${colors.red}24;
            border-color: #${colors.red}66;
            border: ${toString geometry.border}px 0 0 0;
            padding: 0.75em 1em;
            spacing: 0.5em;
            text-color: #${colors.text};
          }

          listview {
            flow: horizontal;
            fixed-columns: true;
            columns: 7;
            lines: 5;
            spacing: 1em;
            scrollbar: false;
          }

          element {
            orientation: vertical;
            padding: 0.65em;
            background-image: linear-gradient(#${colors.surface0}e6, #${colors.base}e6);
            border-color: #${colors.overlay0}55;
            border: ${toString geometry.border}px;
            border-radius: ${toString geometry.radiusMedium}px;
            text-color: #${colors.text};
            children: [ element-icon, element-text ];
          }

          element-icon {
            size: calc(((100% - 8em) / 7));
            horizontal-align: 0.5;
            vertical-align: 0.5;
          }

          element-text {
            horizontal-align: 0.5;
            vertical-align: 0.5;
            padding: 0.45em 0.2em 0.1em;
            text-color: inherit;
          }

          element selected {
            background-image: linear-gradient(#${colors.mauve}, #${colors.lavender});
            border-color: #${colors.lavender};
            text-color: #${colors.crust};
          }

          element selected element-text {
            text-color: #${colors.crust};
          }

          @media ( enabled: env(PREVIEW, false)) {
            icon-current-entry {
              expand: true;
              size: 80%;
            }

            listview-split {
              children: [ listview, icon-current-entry ];
            }

            listview {
              columns: 4;
            }
          }

          @media ( enabled: env(NO_IMAGE, false)) {
            listview {
              columns: 1;
              spacing: 0.5em;
            }

            element {
              orientation: horizontal;
              children: [ element-text ];
            }

            element-text {
              horizontal-align: 0.0;
            }
          }
        '';

        # Compact companion to the fullscreen application browser. The
        # command center, clipboard, calculator, emoji picker, and keybind
        # reference all use this surface so utility menus feel like one tool.
        xdg.configFile."rofi/catppuccin-command-center.rasi".text = ''
          * {
            background-color: transparent;
            text-color: #${colors.text};
            font: "${fonts.sans} 14";
          }

          window {
            width: 720px;
            location: center;
            anchor: center;
            background-image: linear-gradient(#${colors.surface0}ec, #${colors.base}ec);
            border: ${toString geometry.border}px;
            border-color: #${colors.lavender}99;
            border-radius: ${toString geometry.radiusLarge}px;
            padding: 20px;
          }

          mainbox {
            children: [ inputbar, listview, message ];
            spacing: 14px;
          }

          inputbar {
            children: [ prompt, entry ];
            spacing: 12px;
            padding: 12px 14px;
            background-color: #${colors.crust}b8;
            border: 1px;
            border-color: #${colors.overlay0}66;
            border-radius: ${toString geometry.radiusMedium}px;
          }

          prompt {
            text-color: #${colors.mauve};
            font: "${fonts.mono} Bold 13";
          }

          entry {
            placeholder: "Search commands";
            placeholder-color: #${colors.overlay1};
            text-color: #${colors.text};
          }

          listview {
            columns: 1;
            lines: 12;
            fixed-height: false;
            scrollbar: false;
            spacing: 7px;
          }

          element {
            children: [ element-text ];
            padding: 11px 14px;
            background-color: #${colors.surface1}5c;
            border: 1px;
            border-color: #${colors.overlay0}4d;
            border-radius: ${toString geometry.radiusMedium}px;
          }

          element-text {
            text-color: inherit;
            vertical-align: 0.5;
          }

          element selected {
            background-image: linear-gradient(#${colors.mauve}, #${colors.lavender});
            border-color: #${colors.lavender};
            text-color: #${colors.crust};
          }

          element selected element-text {
            text-color: #${colors.crust};
          }

          message {
            padding: 10px 12px;
            background-color: #${colors.red}24;
            border: 1px;
            border-color: #${colors.red}55;
            border-radius: ${toString geometry.radiusSmall}px;
            text-color: #${colors.text};
          }
        '';

        stylix.targets.rofi.enable = false;

        gtk.enable = true;
        home.pointerCursor.enable = true;
      };
    };
}
