{
  homeManager.modules.thorn =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.thorn.programs.firefox;
    in
    {
      options.thorn.programs.firefox.enable =
        lib.mkEnableOption "Thorn's Firefox Home Manager configuration";

      config = lib.mkIf cfg.enable {
        programs.firefox = {
          enable = true;
          languagePacks = [
            "en-US"
          ];

          profiles = {
            default = {
              settings = {
                "browser.startup.homepage" = "http://localhost:8080";
              };
              search = {
                force = true;
                default = "SearXNG";
                privateDefault = "SearXNG";

                engines = {

                  "SearXNG" = {
                    urls = [
                      {
                        template = "https://search.guildedthorn.arpa/search";
                        params = [
                          {
                            name = "q";
                            value = "{searchTerms}";
                          }
                        ];
                      }
                    ];
                    definedAliases = [ "@sx" ];
                  };

                  "Nix Packages" = {
                    urls = [
                      {
                        template = "https://search.nixos.org/packages";
                        params = [
                          {
                            name = "channel";
                            value = "unstable";
                          }
                          {
                            name = "query";
                            value = "{searchTerms}";
                          }
                        ];
                      }
                    ];
                    icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                    definedAliases = [ "@np" ];
                  };

                  "Nix Options" = {
                    urls = [
                      {
                        template = "https://search.nixos.org/options";
                        params = [
                          {
                            name = "channel";
                            value = "unstable";
                          }
                          {
                            name = "query";
                            value = "{searchTerms}";
                          }
                        ];
                      }
                    ];
                    icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                    definedAliases = [ "@no" ];
                  };

                  "NixOS Wiki" = {
                    urls = [
                      {
                        template = "https://wiki.nixos.org/w/index.php";
                        params = [
                          {
                            name = "search";
                            value = "{searchTerms}";
                          }
                        ];
                      }
                    ];
                    icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
                    definedAliases = [ "@nw" ];
                  };
                };
              };
            };
          };

          policies = {
            DisablePocket = true;
            DisableTelemetry = true;
            DisableFormHistory = true;
            DisablePasswordReveal = true;
            ExtensionSettings = {
              "uBlock0@raymondhill.net" = {
                default_area = "menupanel";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
                installation_mode = "force_installed";
                private_browsing = true;
              };
              "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
                default_area = "menupanel";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi";
                installation_mode = "force_installed";
                private_browsing = true;
              };
              "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
                default_area = "menupanel";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
                installation_mode = "force_installed";
                private_browsing = false;
              };
              "addon@darkreader.org" = {
                default_area = "menupanel";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
                installation_mode = "force_installed";
                private_browsing = true;
              };
              "{49aa8e5f-f9d6-4556-a881-010b048e8636}" = {
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/spirited-away/latest.xpi";
                installation_mode = "force_installed";
                updates_disabled = true;
              };
            };

            InstallAddonsPermission = {
              Default = true;
            };
          };
        };

        stylix.targets.firefox.profileNames = [ "default" ];
      };
    };
}
