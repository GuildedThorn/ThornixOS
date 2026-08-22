{
  config,
  lib,
  osConfig,
  ...
}:
let
  mkGmailAccount =
    {
      address,
      secretName,
      primary ? false,
    }:
    {
      inherit address primary;
      userName = address;
      realName = "Jamie Duddleston";
      flavor = "gmail.com";
      passwordCommand = "cat ${osConfig.sops.secrets.${secretName}.path}";
      imap.authentication = "clear";
      smtp.authentication = "clear";
      mbsync.enable = true;
      mbsync.flatten = ".";
      mbsync.expunge = "both";
      # Gmail grows folders over time ([Gmail]/Starred appeared remotely);
      # without this mbsync refuses to open the missing local side and the
      # whole sync unit fails.
      mbsync.create = "maildir";
      # Without this, neomutt's default trash is a local "Trash" folder that
      # has no Gmail counterpart — deletions pile up locally and mbsync
      # fails on the missing far side. Point it at Gmail's actual trash
      # (dot-name because of mbsync.flatten above).
      folders.trash = "[Gmail].Trash";
      msmtp.enable = true;
      notmuch.enable = true;
      neomutt.enable = true;
    };
in
{
  config = lib.mkMerge [
    {
      home.stateVersion = "26.11";
      thorn.desktop.hyprland.enable = true;
      thorn.desktop.rice.enable = true;
      thorn.desktop.wallpaper.enable = true;
      thorn.desktop.crt.enable = true;
      thorn.programs.vesktop.enable = true;
      thorn.programs.firefox.enable = true;
      thorn.programs.ghostty.enable = true;
      thorn.programs.obsidian.enable = true;
      thorn.programs.neomutt.enable = true;
      thorn.programs.claude-code.enable = true;
      thorn.programs.opencode.enable = true;
      thorn.programs.loom-client.enable = true;

      thorn.programs.matcha = {
        enable = true;
        accounts = {
          guildedthorn = {
            email = "guildedthorn@gmail.com";
            secretPath = osConfig.sops.secrets.gmail_guildedthorn_app_password.path;
          };
          opticalpvpx = {
            email = "opticalpvpx@gmail.com";
            secretPath = osConfig.sops.secrets.gmail_opticalpvpx_app_password.path;
          };
          jamieduddleston2 = {
            email = "jamieduddleston2@gmail.com";
            secretPath = osConfig.sops.secrets.gmail_jamieduddleston2_app_password.path;
          };
        };
      };

      thorn.programs.weechat = {
        enable = true;
        servers = {
          # OFTC hosts Kali, Wayland/freedesktop.org, and its own support
          # channel - everything on the requested channel list lives here.
          oftc = {
            address = "irc.oftc.net/6697";
            sslCert = osConfig.sops.secrets.oftc_client_cert.path;
            # OFTC's ircd doesn't advertise the IRCv3 `sasl` capability;
            # it identifies the cert directly at connection registration.
            sasl = false;
            autojoin = [
              "#kali-linux"
              "#oftc"
              "#kali-nethunter"
              "#linux"
              "#home-manager"
              "#wayland"
              "#freedesktop"
            ];
          };
        };
      };

      accounts.email.accounts = {
        guildedthorn = mkGmailAccount {
          address = "guildedthorn@gmail.com";
          secretName = "gmail_guildedthorn_app_password";
          primary = true;
        };
        opticalpvpx = mkGmailAccount {
          address = "opticalpvpx@gmail.com";
          secretName = "gmail_opticalpvpx_app_password";
        };
        jamieduddleston2 = mkGmailAccount {
          address = "jamieduddleston2@gmail.com";
          secretName = "gmail_jamieduddleston2_app_password";
        };
      };
    }
    (lib.mkIf config.thorn.desktop.hyprland.enable {
      wayland.windowManager.hyprland.settings.monitor = [
        {
          output = "desc:Chrontel Inc TV DISPLAY";
          mode = "720x480@60.0";
          # Flush against the HP's right edge (2409+1920) and bottom-aligned
          # with both 1080p panels (3250+1080-480), so a full-desktop grab is
          # one contiguous strip.
          position = "4329x3850";
          # Native 1:1 for the CRT SOC display — fractional downscaling just
          # blurs a tube; the eww widget is designed for 720x480 logical.
          scale = "1.0";
        }
        {
          output = "desc:LG Electronics 24GN50W 0x0006C019";
          mode = "1920x1080@144.0";
          position = "489x3250";
          scale = "1.0";
        }
        {
          output = "desc:HP Inc. HP X24ih 1CR1211S3F";
          mode = "1920x1080@143.98";
          position = "2409x3250";
          scale = "1.0";
        }
      ];

      # Keep application workspaces on the 1080p panels. Without explicit
      # defaults, Hyprland gives workspace 1 (and therefore Steam) to the CRT.
      wayland.windowManager.hyprland.settings.workspace_rule = [
        {
          workspace = "1";
          monitor = "desc:LG Electronics 24GN50W 0x0006C019";
          default = true;
        }
        {
          workspace = "3";
          monitor = "desc:HP Inc. HP X24ih 1CR1211S3F";
          default = true;
        }
        {
          workspace = "name:crt";
          monitor = "desc:Chrontel Inc TV DISPLAY";
          default = true;
        }
      ];

      # Keep the live Wayle layout reproducible. Wayle 0.6 nests layouts
      # under `bar`; root-level `layout` is ignored and previously left the
      # unmanaged runtime.toml as the only working copy.
      services.wayle.settings.bar.layout = [
        {
          monitor = "DP-2";
          show = true;
          left = [
            "custom-thornix"
            "hyprland-workspaces"
            "idle-inhibit"
          ];
          center = [
            {
              name = "now-playing";
              modules = [
                "cava"
                "media"
              ];
            }
          ];
          right = [
            {
              name = "net";
              modules = [
                {
                  module = "clock";
                  class = "primary-clock";
                }
                "world-clock"
              ];
            }
            "systray"
          ];
        }
        {
          monitor = "DP-3";
          show = true;
          left = [
            "hyprland-workspaces"
            {
              name = "specs";
              modules = [
                "cpu"
                "ram"
                "storage"
                "netstat"
              ];
            }
          ];
          center = [ "window-title" ];
          right = [
            {
              name = "audio";
              modules = [
                "volume"
                "microphone"
              ];
            }
            {
              name = "quick";
              modules = [
                "bluetooth"
                "network"
                "hyprsunset"
                "notifications"
              ];
            }
          ];
        }
        {
          # Eww owns the CRT; retain a fallback layout but keep its Wayle bar
          # hidden when the adapter appears as DP-1.
          monitor = "DP-1";
          show = false;
          left = [ "media" ];
          center = [ "clock" ];
          right = [
            "battery"
            "bluetooth"
            "network"
            "microphone"
            "volume"
          ];
        }
      ];
    })
  ];
}
