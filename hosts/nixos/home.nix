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
      thorn.programs.vesktop.enable = false;
      thorn.programs.firefox.enable = true;
      thorn.programs.ghostty.enable = true;
      thorn.programs.obsidian.enable = true;
      thorn.programs.neomutt.enable = true;
      thorn.programs.claude-code.enable = true;

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
          position = "4887x3610";
          scale = "0.670000";
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

      services.wayle.settings = {
        inset-edge = 0.5;
        inset-ends = 0.5;
        layout = [
          {
            center = [
              "cava"
              "media"
            ];
            left = [
              "dashboard"
              "weather"
              "separator"
              "hyprland-workspaces"
              "separator"
              "clock"
              "world-clock"
            ];
            monitor = "DP-2";
            right = [
              "network"
              "netstat"
              "separator"
              "systray"
            ];
            show = true;
          }
          {
            center = [ "window-title" ];
            left = [
              "hyprland-workspaces"
              "separator"
              "cpu"
              "ram"
              "storage"
            ];
            monitor = "DP-3";
            right = [
              "volume"
              "hyprsunset"
              "bluetooth"
              "notifications"
            ];
            show = true;
          }
        ];
      };
    })
  ];
}
