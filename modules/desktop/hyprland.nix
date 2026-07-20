{ inputs, ... }:
{
  nixos.modules.desktop-hyprland =
    {
      pkgs,
      ...
    }:
    let
      # Same image as in ~/Pictures/walls-catppuccin-mocha, but fetched into
      # the store so the greeter user can read it before anyone logs in.
      regreetWallpaper = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/orangci/walls-catppuccin-mocha/master/black-hole.png";
        hash = "sha256-2dl0PP6Ny6i4ImwT97hguoS76X9v96zJJkiTOHrHBFs=";
      };
    in
    {

      #################################
      # Hyprland (Upstream Flake)
      #################################

      programs.hyprland = {
        enable = true;
        # set the flake package
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        # make sure to also set the portal package, so that they are in sync
        portalPackage =
          inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;

        withUWSM = true;
        xwayland.enable = true;
      };

      xdg.portal = {
        enable = true;
        xdgOpenUsePortal = true;

        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        config = {
          hyprland = {
            default = [
              "hyprland"
              "gtk"
            ];
            "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
          };
        };
      };

      #################################
      # Login Manager (greetd + ReGreet)
      #################################

      services.greetd.enable = true;

      # GTK theme + fonts come from stylix's regreet target (Catppuccin Mocha,
      # Geist); this adds the background, cursor, clock, and the login card CSS.
      programs.regreet = {
        enable = true;

        cursorTheme = {
          name = "Bibata-Modern-Ice";
          package = pkgs.bibata-cursors;
        };

        settings = {
          background = {
            path = regreetWallpaper;
            fit = "Cover";
          };
          appearance.greeting_msg = "Welcome back, Thorn";
          widget.clock = {
            format = "%A %d %B · %H:%M";
            resolution = "500ms";
          };
        };

        # Catppuccin Mocha: base #1e1e2e, crust #11111b, surface0 #313244,
        # surface1 #45475a, text #cdd6f4, lavender #b4befe, mauve #cba6f7
        extraCss = ''
          frame {
            background-color: rgba(30, 30, 46, 0.82);
            border: 1px solid rgba(180, 190, 254, 0.25);
            border-radius: 18px;
            padding: 18px;
            box-shadow: 0 12px 32px rgba(17, 17, 27, 0.6);
          }

          label {
            color: #cdd6f4;
          }

          entry {
            background-color: rgba(49, 50, 68, 0.9);
            color: #cdd6f4;
            caret-color: #cba6f7;
            border: 1px solid transparent;
            border-radius: 10px;
            min-height: 34px;
            padding: 0 10px;
          }

          entry:focus-within {
            border-color: #cba6f7;
          }

          button {
            background-color: rgba(49, 50, 68, 0.9);
            color: #cdd6f4;
            border: none;
            border-radius: 10px;
          }

          button:hover {
            background-color: rgba(69, 71, 90, 0.9);
          }

          button.suggested-action {
            background-color: #cba6f7;
            color: #11111b;
            font-weight: 600;
          }

          button.suggested-action:hover {
            background-color: #b4befe;
          }
        '';
      };

      #################################
      # Lock + Idle
      #################################

      programs.hyprlock.enable = true;
      services.hypridle.enable = true;

      #################################
      # Packages
      #################################

      environment.systemPackages = with pkgs; [
        gtk-layer-shell
        hyprpaper
        hyprsunset
        waypaper
        hyprsysteminfo
        swayosd
        libnotify
        inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww
      ];
    };
}
