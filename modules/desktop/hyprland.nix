{ inputs, ... }:
{
  nixos.modules.desktop-hyprland =
    {
      pkgs,
      ...
    }:
    let
      rice = import ../../lib/rice.nix;
      inherit (rice) colors geometry;
      thornixMark = rice.branding.svg pkgs;

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

      # Provide the Secret portal backend selected above and unlock the
      # login keyring through greetd's PAM stack. Keep the GCR SSH agent off:
      # services-ssh already owns SSH_AUTH_SOCK through programs.ssh.startAgent.
      services.gnome.gnome-keyring.enable = true;
      services.gnome.gcr-ssh-agent.enable = false;

      #################################
      # Login Manager (greetd + ReGreet)
      #################################

      services.greetd.enable = true;

      # GTK theme + fonts come from stylix's regreet target (Catppuccin Mocha,
      # Geist); this adds the background, cursor, clock, and the login card CSS.
      programs.regreet = {
        enable = true;

        settings = {
          background = {
            path = regreetWallpaper;
            fit = "Cover";
          };
          appearance.greeting_msg = "THORNIX // Welcome back, Thorn";
          widget.clock = {
            format = "%A %d %B · %H:%M";
            resolution = "500ms";
          };
        };

        # Shared Mocha surfaces and geometry carry the same visual hierarchy
        # through the greeter, lock screen, launcher, bar, and logout overlay.
        extraCss = ''
          frame {
            background-color: rgba(30, 30, 46, 0.86);
            background-image: image(url("${thornixMark}"));
            background-repeat: no-repeat;
            background-position: center 18px;
            background-size: 62px;
            border: ${toString geometry.border}px solid #${colors.mauve}55;
            border-radius: ${toString geometry.radiusLarge}px;
            padding: 92px 18px 18px;
            box-shadow: 0 12px 32px rgba(17, 17, 27, 0.6);
          }

          label {
            color: #${colors.text};
          }

          entry {
            background-color: rgba(49, 50, 68, 0.9);
            color: #${colors.text};
            caret-color: #${colors.mauve};
            border: ${toString geometry.border}px solid transparent;
            border-radius: ${toString geometry.radiusSmall}px;
            min-height: 34px;
            padding: 0 10px;
          }

          entry:focus-within {
            border-color: #${colors.mauve};
          }

          button {
            background-color: rgba(49, 50, 68, 0.9);
            color: #${colors.text};
            border: none;
            border-radius: ${toString geometry.radiusSmall}px;
          }

          button:hover {
            background-color: rgba(69, 71, 90, 0.9);
          }

          button.suggested-action {
            background-color: #${colors.mauve};
            color: #${colors.crust};
            font-weight: 600;
          }

          button.suggested-action:hover {
            background-color: #${colors.lavender};
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

      # swayosd's privileged libinput backend as the dbus-activated system
      # service the package ships (with its polkit and udev rules), replacing
      # the old `pkexec swayosd-libinput-backend` autostart and its polkit
      # prompt at every login.
      systemd.packages = [ pkgs.swayosd ];
      services.dbus.packages = [ pkgs.swayosd ];
      services.udev.packages = [ pkgs.swayosd ];

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
