{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/mitm/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.mitm = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core
      config.nixos.modules.services-ssh
      config.nixos.modules.services-thorncloud-acme

      "${inputs.self}/hosts/mitm/hardware-configuration.nix"
      "${inputs.self}/hosts/mitm/disko.nix"
      "${inputs.self}/hosts/mitm/networking.nix"

      {
        boot.loader = {
          systemd-boot.enable = true;
          efi.canTouchEfiVariables = true;
        };
        boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

        hardware.bluetooth = {
          enable = true;
          powerOnBoot = true;
        };

        services.home-assistant = {
          enable = true;
          openFirewall = false;
          openFirewallForComponents = true;
          extraComponents = [
            "analytics"
            "bluetooth"
            "co2signal"
            "default_config"
            "esphome"
            "google_translate"
            "govee_ble"
            "isal"
            "jellyfin"
            "met"
            "radio_browser"
            "shopping_list"
            "ssdp"
            "wyoming"
            "zeroconf"
          ];
          config = {
            default_config = { };
            frontend.themes.Thorn = {
              "accent-color" = "#68aee8";
              "app-header-background-color" = "#0d1117";
              "app-header-text-color" = "#e6edf3";
              "card-background-color" = "#151d27";
              "divider-color" = "rgba(151, 166, 181, 0.16)";
              "ha-card-border-radius" = "18px";
              "ha-card-border-width" = "0px";
              "ha-card-box-shadow" = "0 8px 28px rgba(0, 0, 0, 0.28)";
              "primary-background-color" = "#0d1117";
              "primary-color" = "#d8a657";
              "primary-text-color" = "#e6edf3";
              "secondary-background-color" = "#111821";
              "secondary-text-color" = "#9ca9b7";
            };
            http = {
              server_host = "127.0.0.1";
              trusted_proxies = [ "127.0.0.1" ];
              use_x_forwarded_for = true;
            };
            lovelace.dashboards."thorn-home" = {
              mode = "yaml";
              filename = "thorn-home.yaml";
              title = "Thorn Home";
              icon = "mdi:shield-home-outline";
              show_in_sidebar = true;
            };
            automation = [
              {
                id = "pineapple_wireless_security_alert";
                alias = "Pineapple wireless security alert";
                mode = "queued";
                triggers = [
                  {
                    trigger = "webhook";
                    webhook_id = "pineapple-wifi-watch-6f4b2c1d9a8e7350";
                    allowed_methods = [ "POST" ];
                    local_only = true;
                  }
                ];
                actions = [
                  {
                    action = "persistent_notification.create";
                    data = {
                      title = "Wireless security alert";
                      message = "{{ trigger.json.message | default('Wireless anomaly detected') }}";
                      notification_id = "pineapple_wifi_watch";
                    };
                  }
                ];
              }
            ];
          };
        };

        services.wyoming = {
          piper.servers.english = {
            enable = true;
            uri = "tcp://127.0.0.1:10200";
            voice = "en_US-lessac-medium";
            zeroconf.enable = false;
          };
          faster-whisper.servers.english = {
            enable = true;
            uri = "tcp://127.0.0.1:10300";
            model = "base-int8";
            language = "en";
            sttLibrary = "faster-whisper";
            device = "cpu";
            zeroconf.enable = false;
          };
          openwakeword = {
            enable = true;
            uri = "tcp://127.0.0.1:10400";
          };
        };

        systemd.tmpfiles.rules = [
          "L+ /var/lib/hass/thorn-home.yaml - - - - ${inputs.self}/hosts/mitm/thorn-home.yaml"
        ];

        thorn.acme = {
          enable = true;
          domain = "mitm.guildedthorn.arpa";
        };

        services.nginx = {
          enable = true;
          recommendedGzipSettings = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;
          virtualHosts."mitm.guildedthorn.arpa" = {
            serverName = "mitm.guildedthorn.arpa";
            forceSSL = true;
            useACMEHost = "mitm.guildedthorn.arpa";
            extraConfig = ''
              add_header X-Content-Type-Options "nosniff" always;
              add_header Referrer-Policy "same-origin" always;
            '';
            locations."/" = {
              proxyPass = "http://127.0.0.1:8123";
              proxyWebsockets = true;
            };
            locations."= /pineapple-wifi-watch" = {
              proxyPass = "http://127.0.0.1:8123/api/webhook/pineapple-wifi-watch-6f4b2c1d9a8e7350";
              extraConfig = ''
                allow 192.168.1.31;
                deny all;
                proxy_set_header Content-Type application/json;
              '';
            };
          };
        };

        services.openssh.settings = {
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;
          PermitRootLogin = "prohibit-password";
        };
        users.users.root = {
          initialHashedPassword = "!";
          openssh.authorizedKeys.keys = adminSshKeys;
        };
      }
    ];
  };
}
