{
  # Window rules (workspace assignment, screenshare protection), isolated so
  # a bad match regex can be disabled per-host without touching anything else:
  # thorn.desktop.hyprland.windowRules.enable = false.
  homeManager.modules.thorn =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.thorn.desktop.hyprland;
    in
    {
      options.thorn.desktop.hyprland.windowRules.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hyprland window rules.";
      };

      config = lib.mkIf (cfg.enable && cfg.windowRules.enable) {
        wayland.windowManager.hyprland.settings.window_rule = [
          {
            name = "noscreenshare";
            no_screen_share = 1;
            match.class = "^(?i)(.*keepassxc.*)$";
          }

          {
            workspace = "1";
            match.class = "^(vesktop|Vesktop|discord|Discord|Spotify|spotify|steam|Steam)$";
          }

          {
            workspace = "2";
            match.class = "^(ghostty|Ghostty|com\\.mitchellh\\.ghostty|kitty|Alacritty|org\\.wezfurlong\\.wezterm)$";
          }

          {
            workspace = "3";
            match.class = "^(firefox|Firefox|librewolf|LibreWolf|zen|Zen|chromium|Chromium|google-chrome|Google-chrome|brave-browser|Brave-browser)$";
          }

          {
            workspace = "4";
            match.class = "^(irssi|signal|Signal|org\\.telegram\\.desktop|TelegramDesktop)$";
          }

          {
            workspace = "5";
            match.class = "^(code|Code|codium|Codium|code-url-handler|obsidian|Obsidian|jetbrains-.+|jetbrains-idea|jetbrains-pycharm|jetbrains-webstorm)$";
          }
        ];
      };
    };
}
