{ inputs, ... }:
{
  homeManager.modules.thorn =
    {
      pkgs,
      lib,
      ...
    }:
    let
      # arc-theme's unstable snapshot fails to build its gnome-shell/cinnamon
      # variants against GNOME Shell 50 (missing 45/icons dir upstream).
      # This fleet runs Hyprland, so build only the GTK/X11 theme variants.
      arc-theme = pkgs.arc-theme.overrideAttrs (old: {
        mesonFlags = (lib.filter (f: !(lib.hasPrefix "-Dthemes=" f)) old.mesonFlags) ++ [
          (lib.mesonOption "themes" "gtk3,gtk4,metacity,plank,unity,xfwm")
        ];
      });
    in
    {

      imports = [
        inputs.nixvim.homeModules.nixvim
      ];

      home.stateVersion = "26.11";
      home.pointerCursor.enable = true;

      # Add required packages to the user's environment
      home.packages = with pkgs; [
        arc-theme

        yubioath-flutter
        yubikey-manager
        yubikey-personalization
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

      nixpkgs.config.allowUnfree = true;

      programs.intelli-shell = {
        enable = true;
        enableZshIntegration = true;
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

      services.playerctld = {
        enable = true;
      };

      programs.gpg.enable = true;

      # scdaemon settings -> will create the equivalent lines in ~/.gnupg/scdaemon.conf
      programs.gpg.scdaemonSettings = {
        disable-ccid = true;
        pcsc-shared = true;
      };

      programs.feh.enable = true;

      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        package = inputs.yazi.packages.${pkgs.stdenv.hostPlatform.system}.default;
        plugins = {
          inherit (pkgs.yaziPlugins) mount;
        };
        keymap.mgr.prepend_keymap = [
          {
            on = "M";
            run = "plugin mount";
            desc = "Mount, unmount, or eject a drive";
          }
        ];
        settings = {
          mgr = {
            ratio = [
              1
              4
              3
            ];
            sort_by = "natural";
            sort_sensitive = true;
            sort_reverse = false;
            sort_dir_first = true;
            linemode = "none";
            show_hidden = true;
            show_symlink = true;
          };

          preview = {
            image_filter = "lanczos3";
            image_quality = 90;
            tab_size = 1;
            max_width = 600;
            max_height = 900;
            cache_dir = "";
            ueberzug_scale = 1;
            ueberzug_offset = [
              0
              0
              0
              0
            ];
          };

          tasks = {
            bizarre_retry = 5;
          };
        };
      };

      stylix.targets.yazi.enable = true;

      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
      };

      programs.fastfetch = {
        enable = true;
      };

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
}
