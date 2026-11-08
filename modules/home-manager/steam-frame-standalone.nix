{
  inputs,
  config,
  ...
}:
{
  # Standalone Home Manager profile for the Steam Frame while it still runs
  # SteamOS. Unlike "thorn@remote" this evaluates for aarch64 and uses
  # genericLinux integration, so it can be activated on the headset itself:
  #
  #   nix run home-manager/master -- switch --flake .#steamos@frame
  #
  # or, after installing Nix on the Frame:
  #
  #   home-manager switch --flake github:GuildedThorn/ThornixOS#steamos@frame
  #
  # The SteamOS root filesystem stays read-only; everything this profile
  # manages lives under /home/steamos.
  flake.homeConfigurations."steamos@frame" = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "aarch64-linux";
      config.allowUnfree = true;
    };

    modules = [
      config.homeManager.modules.steam-frame

      {
        home.username = "steamos";
        home.homeDirectory = "/home/steamos";
        home.stateVersion = "26.11";

        # Non-NixOS integration. GPU driver setup is skipped: it writes to
        # /etc, which SteamOS resets on every update, and the Frame's
        # gamescope session already provides the working graphics stack.
        targets.genericLinux.enable = true;
        targets.genericLinux.gpu.enable = false;

        programs.home-manager.enable = true;
        news.display = "silent";

        thorn.steamFrame = {
          enable = true;
          keyboard.layout = "us";
        };
      }
    ];
  };
}
