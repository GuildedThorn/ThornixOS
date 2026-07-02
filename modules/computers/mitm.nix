{ config, inputs, ... }:
{
  flake.nixosConfigurations.mitm = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-clamav
      config.nixos.modules.services-ssh

      "${inputs.self}/hosts/mitm/hardware-configuration.nix"
      "${inputs.self}/hosts/mitm/networking.nix"

      (
        { config, lib, ... }:
        {
          services.nginx = {
            enable = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;
            recommendedGzipSettings = true;
            recommendedOptimisation = true;
            virtualHosts = {
              "guildedthorn.com" = {
                serverName = "guildedthorn.com";
                useACMEHost = "guildedthorn.com";
                acmeRoot = "/var/lib/acme/challenges-guildedthorn";
                forceSSL = true;
                locations."/" = {
                  proxyPass = "https://proxmox.guildedthorn.arpa:5000";
                };
              };
              "radio.guildedthorn.com" = {
                serverName = "radio.guildedthorn.com";
                useACMEHost = "guildedthorn.com";
                acmeRoot = "/var/lib/acme/challenges-guildedthorn";
                forceSSL = true;
                locations."/" = {
                  proxyPass = "https://proxmox.guildedthorn.arpa:5001";
                };
              };
              "searxng.guildedthorn.arpa" = {
                serverName = "searxng.guildedthorn.arpa";
                sslCertificate = "...";
                sslCertificateKey = "...";
                locations."/" = {
                  extraConfig = ''
                    uwsgi_pass unix:${config.services.searx.uwsgiConfig.socket};
                  '';
                };
              };
            };
          };

          services.technitium-dns-server = {
            enable = true;
            openFirewall = true;
          };

          #services.mongodb = {
          #enable = true;
          #  enableAuth = true;
          #};

          services.searx = {
            enable = false;
            redisCreateLocally = true;

            # Rate limiting
            limiterSettings = {
              real_ip = {
                x_for = 1;
                ipv4_prefix = 32;
                ipv6_prefix = 56;
              };

              botdetection = {
                ip_limit = {
                  filter_link_local = true;
                  link_token = true;
                };
              };
            };

            # UWSGI configuration
            runInUwsgi = true;

            uwsgiConfig = {
              socket = "/run/searx/searx.sock";
              http = ":8888";
              chmod-socket = "660";
            };

            # Searx configuration
            settings = {
              # Instance settings
              general = {
                debug = false;
                instance_name = "SearXNG Instance";
                donation_url = false;
                contact_url = false;
                privacypolicy_url = false;
                enable_metrics = false;
              };

              # User interface
              ui = {
                static_use_hash = true;
                default_locale = "en";
                query_in_title = true;
                infinite_scroll = false;
                center_alignment = true;
                default_theme = "simple";
                theme_args.simple_style = "auto";
                search_on_category_select = false;
                hotkeys = "vim";
              };

              # Search engine settings
              search = {
                safe_search = 2;
                autocomplete_min = 2;
                autocomplete = "duckduckgo";
                ban_time_on_fail = 5;
                max_ban_time_on_fail = 120;
              };

              # Server configuration
              server = {
                base_url = "https://searxng.guildedthorn.arpa";
                port = 8888;
                bind_address = "127.0.0.1";
                secret_key = config.sops.secrets.searx.path;
                limiter = true;
                public_instance = true;
                image_proxy = true;
                method = "GET";
              };

              # Search engines
              engines = lib.mapAttrsToList (name: value: { inherit name; } // value) {
                "duckduckgo".disabled = false;
                "brave".disabled = false;
                "bing".disabled = false;
                "mojeek".disabled = true;
                "mwmbl".disabled = false;
                "mwmbl".weight = 0.4;
                "qwant".disabled = true;
                "crowdview".disabled = false;
                "crowdview".weight = 0.5;
                "curlie".disabled = true;
                "ddg definitions".disabled = false;
                "ddg definitions".weight = 2;
                "wikibooks".disabled = false;
                "wikidata".disabled = false;
                "wikiquote".disabled = true;
                "wikisource".disabled = true;
                "wikispecies".disabled = false;
                "wikispecies".weight = 0.5;
                "wikiversity".disabled = false;
                "wikiversity".weight = 0.5;
                "wikivoyage".disabled = false;
                "wikivoyage".weight = 0.5;
                "currency".disabled = true;
                "dictzone".disabled = true;
                "lingva".disabled = true;
                "bing images".disabled = false;
                "brave.images".disabled = true;
                "duckduckgo images".disabled = true;
                "google images".disabled = false;
                "qwant images".disabled = true;
                "1x".disabled = true;
                "artic".disabled = false;
                "deviantart".disabled = false;
                "flickr".disabled = true;
                "imgur".disabled = false;
                "library of congress".disabled = false;
                "material icons".disabled = true;
                "material icons".weight = 0.2;
                "openverse".disabled = false;
                "pinterest".disabled = true;
                "svgrepo".disabled = false;
                "unsplash".disabled = false;
                "wallhaven".disabled = false;
                "wikicommons.images".disabled = false;
                "yacy images".disabled = true;
                "bing videos".disabled = false;
                "brave.videos".disabled = true;
                "duckduckgo videos".disabled = true;
                "google videos".disabled = false;
                "qwant videos".disabled = false;
                "dailymotion".disabled = true;
                "google play movies".disabled = true;
                "invidious".disabled = true;
                "odysee".disabled = true;
                "peertube".disabled = false;
                "piped".disabled = true;
                "rumble".disabled = false;
                "sepiasearch".disabled = false;
                "vimeo".disabled = true;
                "youtube".disabled = false;
                "brave.news".disabled = true;
                "google news".disabled = true;
              };

              # Outgoing requests
              outgoing = {
                request_timeout = 5.0;
                max_request_timeout = 15.0;
                pool_connections = 100;
                pool_maxsize = 15;
                enable_http2 = true;
              };

              # Enabled plugins
              enabled_plugins = [
                "Basic Calculator"
                "Hash plugin"
                "Tor check plugin"
                "Open Access DOI rewrite"
                "Hostnames plugin"
                "Unit converter plugin"
                "Tracker URL remover"
              ];
            };
          };

          users.users.nginx.extraGroups = [ "acme" ];
          users.groups.searx.members = [ "nginx" ];

          systemd.services.nginx.serviceConfig.ProtectHome = false;

          security.acme = {
            acceptTerms = true;
            defaults.email = "admin@guildedthorn.com";
            certs = {
              "guildedthorn.com" = {
                webroot = "/var/lib/acme/challenges-guildedthorn";
                email = "admin@guildedthorn.com";
                group = "nginx";
                extraDomainNames = [
                  "radio.guildedthorn.com"
                ];
              };
            };
          };
        }
      )
    ];
  };
}
