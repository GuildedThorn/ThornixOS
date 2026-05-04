{
  pkgs,
  inputs,
  ...
}:
{

  imports = [
    inputs.ags.homeManagerModules.default
    inputs.nixvim.homeModules.nixvim
  ];

  home.stateVersion = "26.05";

  # Add required packages to the user's environment
  home.packages = with pkgs; [
    arc-theme

    yubioath-flutter
    yubikey-manager
    yubikey-personalization

    gnome-calculator
    anki-bin
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    oh-my-zsh.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      nix-rebuild = "sudo nixos-rebuild switch --flake /etc/nixos --upgrade";
    };
  };

  programs.eww = {
    enable = true;
    configDir = ./programs/eww;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.nixvim.nixpkgs.config.allowUnfree = true;
  programs.nixvim.imports = [ ./programs/nixvim/main.nix ];

  programs.ags = {
    enable = true;

    configDir = toString ./programs/ags;

    # additional packages and executables to add to gjs's runtime
    extraPackages = with pkgs; [
      inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}.battery
      inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}.powerprofiles
      inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}.io
      inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}.network
      inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}.tray
      inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}.mpris
      inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}.apps
      inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}.wireplumber
      fzf
    ];
  };

  nixpkgs.config.allowUnfree = true;

  programs.obsidian = {
    enable = true;
  };

  programs.vesktop = {
    enable = true;
    settings = {
      arRPC = true;
      hardwareAcceleration = true;
      minimizeToTray = true;
      checkUpdates = true;
      tray = true;
      discordBranch = "canary";
    };

    vencord = {
      settings = {
        autoUpdate = true;
        autoUpdateNotification = true;
        notifyAboutUpdates = false;

        plugins = {
          MessageLogger = {
            enabled = true;
            ignoreSelf = true;
          };
          FixSpotifyEmbeds.enabled = true;
          SpotifyControls.enabled = true;
          SpotifyCrack.enabled = true;
          SilentTyping.enabled = true;
          USRGB.enabled = true;
          ValidUser.enabled = true;
          YoutubeAdBlock.enabled = true;
          ShowHiddenChannels.enabled = true;
          PlatformIndicators.enabled = true;
          Translate.enabled = true;
          FakeNitro.enabled = true;
        };
      };
    };
  };

  programs.intelli-shell = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.hyprshot = {
    enable = true;
    saveLocation = "/home/thorn/Pictures/screenshots";
  };

  programs.ghostty = {
    enable = true;
    systemd.enable = true;
    enableZshIntegration = true;
    installBatSyntax = true;
    installVimSyntax = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = true;
      sync_frequency = "10m";
      style = "compact";
      search_mode = "fuzzy";
    };
  };

  programs.rofi = {
    enable = true;
    theme = "fullscreen-preview.rasi";
  };
  stylix.targets.rofi.enable = false;

  programs.hyprpanel = {
    enable = true;
    systemd.enable = true;
    # Configure and theme almost all options from the GUI.
    # See 'https://hyprpanel.com/configuration/settings.html'.
    # Default: <same as gui>
    settings = {

      # Configure bar layouts for monitors.
      # See 'https://hyprpanel.com/configuration/panel.html'.
      # Default: null
      bar.battery.label = true;
      bar.bluetooth.label = true;
      bar.clock.format = "%H:%M";

      bar.launcher.autoDetectIcon = true;
      bar.workspaces.show_icons = true;

      menus.clock = {
        time = {
          military = true;
          hideSeconds = true;
        };
        weather.unit = "metric";
      };

      menus.dashboard.directories.enabled = false;
      menus.dashboard.stats.enable_gpu = false;

      theme.bar.transparent = true;
      theme.bar.auto_hide = "fullscreen";

      theme.font = {
        name = "CaskaydiaCove NF";
        size = "16px";
      };
    };
  };

  programs.wlogout = {
    enable = true;
  };

  services.mako = {
    enable = false;
    settings = {
      border-size = 2;
      border-radius = 8;
      default-timeout = 5000;
      padding = "12,20";
      margin = "10";
      icons = true;
    };
  };

  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    name = "Bibata-Modern-Ice";
    size = 24;
    package = pkgs.bibata-cursors;
  };

  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;

    plugins = [
      #inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.hyprbars
      inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.hyprexpo
    ];

    settings = {

      #################################
      # Autostart
      #################################

      exec-once = [
        "hyprpaper"
        "pkexec swayosd-libinput-backend"
      ];

      #################################
      # Mod Key
      #################################

      "$mod" = "SUPER";

      #################################
      # General
      #################################

      general = {
        gaps_in = 6;
        gaps_out = 10;
        border_size = 2;

        resize_on_border = true;
        allow_tearing = false;
        layout = "dwindle";
      };

      input = {
        follow_mouse = 0;
        sensitivity = 0.5; # slightly faster for large monitors
        repeat_rate = 35;
        repeat_delay = 250;

        touchpad = {
          natural_scroll = false;
        };
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
        smart_split = false;
        smart_resizing = true;
      };

      plugin = {
        hyprexpo = {
          columns = 3;
          gap_size = 8;
          bg_col = "rgb(30,30,30)";
          workspace_method = "center current";
          gesture_distance = 300;
        };
      };

      #################################
      # Decoration
      #################################

      decoration = {
        rounding = 12;

        blur = {
          enabled = true;
          size = 6;
          passes = 2;
        };

        shadow = {
          enabled = true;
          range = 16;
          render_power = 3;
        };
      };

      #################################
      # Animations
      #################################

      animations = {
        enabled = true;

        bezier = [
          "smooth,0.25,0.1,0.25,1.0"
          "overshot,0.18,0.88,0.22,1.03"
          "fast,0.2,0.75,0.25,1.0"
          "gentle,0.3,0.15,0.25,1.0"
        ];

        animation = [
          "windows,1,6,smooth,slide"
          "windows,1,5,smooth,slide"
          "windowsIn,1,4,overshot,slide"

          "border,1,6,gentle"
          "borderangle,1,5,gentle"

          "fade,1,6,smooth"

          "workspaces,1,5,smooth,slidevert"

          "layers,1,5,gentle,fade"

          "specialWorkspace,1,6,overshot,slidefadevert"

          "windowsMove,1,5,fast,slide"
        ];
      };

      #################################
      # Rendering
      #################################

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        focus_on_activate = true;
        vrr = 1;
      };

      workspace_rules = [
        "workspace:1, class:^(firefox|qutebrowser)$"
        "workspace:2, class:^(kitty|ghostty)$"
        "workspace:3, class:^(thunderbird)$"
        "workspace:4, class:^(code|obsidian)$"
      ];

      #################################
      # Keybinds
      #################################

      bind = [

        # Terminal
        "$mod, return, exec, ghostty +new-window"

        # Calculator
        "$mod, c, exec, gnome-calculator"

        # Email / Calender
        "$mod, v, exec, thunderbird"

        # Firefox
        "$mod, b, exec, firefox"

        # Kill Window
        "$mod, q, killactive"

        # Workspace Switching
        "$mod SHIFT, Tab, workspace, m-1"
        "$mod, Tab, workspace, m+1"
        "$mod right, Tab, workspace, next"
        "$mod left, Tab, workspace, previous"

        # Resize
        "$mod CTRL, left, resizeactive, -20 0"
        "$mod CTRL, right, resizeactive, 20 0"
        "$mod CTRL, up, resizeactive, 0 -20"
        "$mod CTRL, down, resizeactive, 0 20"

        # Focus
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"

        # Move Window
        "$mod SHIFT, left, movewindow, l"
        "$mod SHIFT, right, movewindow, r"
        "$mod SHIFT, up, movewindow, u"
        "$mod SHIFT, down, movewindow, d"

        # Rofi
        "$mod, S, exec, rofi -show window"
        "$mod, D, exec, rofi -show drun"
        "$mod, O, exec, rofi -modi 'obsidian:rofi-obsidian' -show obsidian"

        "$mod, G, hyprexpo:expo, toggle"

        "$mod SHIFT, F1, layoutmsg, setlayout monocle"
        "$mod SHIFT, F4, layoutmsg, setlayout scrolling"
        "$mod SHIFT, F2, layoutmsg, setlayout dwindle"

        # Brightness Control
        ", XF86MonBrightnessUp, exec, swayosd-client --brightness raise"
        ", XF86MonBrightnessDown, exec, swayosd-client --brightness lower"

        # Audio
        ", XF86AudioPlay, exec, swayosd-client --playerctl play-pause"
        ", XF86AudioNext, exec, swayosd-client --playerctl next"
        ", XF86AudioPrev, exec, swayosd-client --playerctl previous"
        ", XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, exec, swayosd-client --output-volume lower"
        ", XF86AudioMicMute, exec, swayosd-client --input-volume=mute-toggle"

        # Caps Lock, Num Lock and Num Lock popup
        ", Caps_Lock, exec, swayosd-client --caps-lock"
        ", Num_Lock, exec, swayosd-client --num-lock"
        ", Scroll_Lock, exec, swayosd-client --scroll-lock"

        # WLAN Toggle
        ", XF86WLAN, exec, swayosd-client --custom-message 'WLAN Toggled'"

        ", XF86Calculator, exec, gnome-calculator"

        ", XF86Display, exec, nwg-displays"

        # Screenshots
        ", PRINT, exec, hyprshot -m output -o /home/thorn/Pictures/screenshots"
        "$mod, PRINT, exec, hyprshot -m window -c -o /home/thorn/Pictures/screenshots"
        "$mod SHIFT, PRINT, exec, hyprshot -m region -o /home/thorn/Pictures/screenshots"

        # Logout
        "$mod, L, exec, wlogout"

        # Fullscreen
        "$mod, F, fullscreen"
        "$mod CTRL, F, fullscreenstate, 0 2"
      ]
      ++ (builtins.concatLists (
        builtins.genList (
          i:
          let
            ws = i + 1;
          in
          [
            "$mod, code:1${toString i}, workspace, ${toString ws}"
            "$mod SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
          ]
        ) 9
      ));
    };
  };

  services.hyprpaper = {
    enable = true;
    settings = {
      splash = true;
      ipc = "on";
    };
  };

  services.cliphist.enable = true;
  services.swayosd.enable = true;

  programs.freetube.enable = true;

  programs.firefox = {
    enable = true;
    languagePacks = [
      "en-US"
    ];

    profiles = {
      default = {
        settings = {
          # Set homepage
          "browser.startup.homepage" = "http://localhost:8080";
        };
        search = {
          force = true;
          default = "ddg";
          privateDefault = "ddg";

          engines = {
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

  programs.irssi = {
    enable = true;
    networks = {
      freenode = {
        nick = "guildedthorn";
        server = {
          address = "chat.freenode.net";
          port = 6697;
          autoConnect = true;
        };
      };
    };
  };

  services.playerctld = {
    enable = true;
  };

  programs.neomutt = {
    enable = true;
  };

  programs.gpg.enable = true;

  # scdaemon settings -> will create the equivalent lines in ~/.gnupg/scdaemon.conf
  programs.gpg.scdaemonSettings = {
    disable-ccid = true;
    pcsc-shared = true;
  };

  programs.feh.enable = true;

  programs.ranger = {
    enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.newsboat = {
    enable = true;
    autoReload = true;
    reloadTime = 10;
  };

  programs.fastfetch = {
    enable = true;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

}
