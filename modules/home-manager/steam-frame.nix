{
  homeManager.modules.steam-frame =
    { config, lib, ... }:
    let
      cfg = config.thorn.steamFrame;
      runtimeDir = cfg.session.runtimeDir;
      busAddress = "unix:path=${runtimeDir}/bus";
      sessionEnv = "XDG_RUNTIME_DIR=${lib.escapeShellArg runtimeDir} DBUS_SESSION_BUS_ADDRESS=${lib.escapeShellArg busAddress}";
      portalDir = "xdg-desktop-portal/gamescope-portals";
    in
    {
      # -----------------------------------------------------------------------
      # Valve Steam Frame (SteamOS, aarch64) Home Manager integration
      # -----------------------------------------------------------------------
      #
      # The Frame runs two graphical sessions: gamescope/SteamVR on the
      # hardware, and a nested KDE Plasma desktop. Home Manager usually runs
      # from the nested desktop, whose XDG_RUNTIME_DIR and D-Bus are private.
      # The user service manager and the running kwalletd live in the Steam
      # session instead (uid 1000, /run/user/1000), so activation has to reach
      # that session explicitly.
      #
      # These options only touch files under $HOME; SteamOS' read-only root
      # filesystem and its A/B update mechanism are left alone.
      options.thorn.steamFrame = {
        enable = lib.mkEnableOption "Steam Frame Home Manager integration";

        session = {
          runtimeDir = lib.mkOption {
            type = lib.types.str;
            default = "/run/user/1000";
            description = "XDG_RUNTIME_DIR of the Steam (outer) session.";
          };

          bus = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            default = busAddress;
            defaultText = lib.literalExpression ''"unix:path=''${config.thorn.steamFrame.session.runtimeDir}/bus"'';
            description = "D-Bus address of the Steam session.";
          };

          services = {
            start = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "docker.service" ];
              description = "User units started on switch if they are not running.";
            };
            restart = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "xdg-desktop-portal.service" ];
              description = "User units restarted on every switch.";
            };
            stop = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "User units stopped on switch if they are running.";
            };
          };
        };

        keyboard = {
          layout = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "us";
            description = ''
              XKB layout for the Steam session. gamescope defaults to US;
              KDE's layout setting only covers the nested desktop. Changes
              take effect at the next Steam session start.
            '';
          };
          variant = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "nodeadkeys";
            description = "XKB variant for the Steam session.";
          };
        };

        applicationsMenu.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Link ~/.config/menus/applications.menu to Plasma's menu, so KDE
            applications started from Steam's "+" menu can see installed
            applications.
          '';
        };

        portalFix = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Provide gamescope-portals.conf for the Steam session's
              xdg-desktop-portal. SteamOS 0.5.x already ships it, so this is
              only needed on older images.
            '';
          };
          fileChooser = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Use KDE's file dialog for the Steam session's FileChooser
              portal, so Flatpak applications can reach files outside their
              sandbox. Requires portalFix.enable.
            '';
          };
        };
      };

      config = lib.mkIf cfg.enable {
        # Reload the Steam session's user manager. Home Manager's own
        # reloadSystemd step talks to the nested desktop's manager (or skips
        # when it cannot reach one), so run this against the outer session.
        home.activation.steamFrameReloadUserManager = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if [ -S ${lib.escapeShellArg "${runtimeDir}/bus"} ] && [ -x /usr/bin/systemctl ]; then
            ${sessionEnv} /usr/bin/systemctl --user daemon-reload || true
          fi
        '';

        home.activation.steamFrameUserServices = lib.hm.dag.entryAfter [ "steamFrameReloadUserManager" ] (
          ''
            (
            export XDG_RUNTIME_DIR=${lib.escapeShellArg runtimeDir}
            export DBUS_SESSION_BUS_ADDRESS=${lib.escapeShellArg busAddress}

            if [ -S ${lib.escapeShellArg "${runtimeDir}/bus"} ] && [ -x /usr/bin/systemctl ]; then
          ''
          + lib.optionalString (cfg.session.services.start != [ ]) ''
            run /usr/bin/systemctl --user start ${lib.escapeShellArgs cfg.session.services.start}
          ''
          + lib.optionalString (cfg.session.services.stop != [ ]) ''
            for unit in ${lib.escapeShellArgs cfg.session.services.stop}; do
              [[ $(/usr/bin/systemctl --user show -p ActiveState --value "$unit") == inactive ]] \
                || run /usr/bin/systemctl --user stop "$unit" || true
            done
          ''
          + lib.optionalString (cfg.session.services.restart != [ ]) ''
            run /usr/bin/systemctl --user restart ${lib.escapeShellArgs cfg.session.services.restart}
          ''
          + ''
            fi
            )
          ''
        );

        # KDE applications build ksycoca from applications.menu. SteamOS only
        # ships plasma-applications.menu; the nested desktop sets
        # XDG_MENU_PREFIX=plasma-, the Steam session does not.
        xdg.configFile."menus/applications.menu" = lib.mkIf cfg.applicationsMenu.enable {
          source = config.lib.file.mkOutOfStoreSymlink "/etc/xdg/menus/plasma-applications.menu";
        };

        # gamescope reads XKB_DEFAULT_* only when it starts. environment.d is
        # not read on the Frame, so the drop-in is the reliable place.
        xdg.configFile."systemd/user/gamescope-session.service.d/keyboard.conf" =
          lib.mkIf (cfg.keyboard.layout != null || cfg.keyboard.variant != null)
            {
              text =
                "[Service]\n"
                + lib.optionalString (
                  cfg.keyboard.layout != null
                ) "Environment=XKB_DEFAULT_LAYOUT=${cfg.keyboard.layout}\n"
                + lib.optionalString (
                  cfg.keyboard.variant != null
                ) "Environment=XKB_DEFAULT_VARIANT=${cfg.keyboard.variant}\n";
            };

        # Older SteamOS images point xdg-desktop-portal at a gamescope-portals
        # directory without a .conf, so no backend is selected and links do
        # not open. Build a user-owned directory around Valve's .portal files.
        xdg.dataFile."${portalDir}/holo.portal" = lib.mkIf cfg.portalFix.enable {
          source = config.lib.file.mkOutOfStoreSymlink "/usr/share/xdg-desktop-portal/gamescope-portals/holo.portal";
        };
        xdg.dataFile."${portalDir}/gamescope.portal" = lib.mkIf cfg.portalFix.enable {
          source = config.lib.file.mkOutOfStoreSymlink "/usr/share/xdg-desktop-portal/gamescope-portals/gamescope.portal";
        };
        xdg.dataFile."${portalDir}/gamescope-portals.conf" = lib.mkIf cfg.portalFix.enable {
          text =
            "[preferred]\n"
            + "default=holo;gamescope\n"
            + lib.optionalString cfg.portalFix.fileChooser "org.freedesktop.impl.portal.FileChooser=kde\n";
        };
        xdg.dataFile."${portalDir}/kde.portal" =
          lib.mkIf (cfg.portalFix.enable && cfg.portalFix.fileChooser)
            {
              source = config.lib.file.mkOutOfStoreSymlink "/usr/share/xdg-desktop-portal/gamescope-portals/kde.portal";
            };
        xdg.configFile."systemd/user/xdg-desktop-portal.service.d/gamescope-portals.conf" =
          lib.mkIf cfg.portalFix.enable
            {
              text = ''
                [Service]
                Environment=XDG_DESKTOP_PORTAL_DIR=%h/.local/share/${portalDir}
              '';
            };
      };
    };
}
