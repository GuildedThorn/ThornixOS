{
  pkgs,
  inputs,
  ...
}:
{

  imports = [
    ./modules/desktop-rice.nix
    ./modules/firefox.nix
    ./modules/ghostty.nix
    ./modules/hyprland.nix
    ./modules/obsidian.nix
    ./modules/xfce-i3.nix
    ./modules/vesktop.nix
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

  programs.nixvim.nixpkgs.config.allowUnfree = true;
  programs.nixvim.imports = [ ./programs/nixvim/main.nix ];

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
    settings = {
      mgr = {
        show_hidden = true;
      };
      yazi = {
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
        micro_workers = 5;
        macro_workers = 10;
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
}
