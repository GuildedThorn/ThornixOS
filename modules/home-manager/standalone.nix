{ inputs, config, ... }:
{
  # Standalone Home Manager profile: just the nixvim editor config from this
  # flake, for applying on a machine without touching its NixOS config.
  # Clone this repo, then:
  #   nix build '.#homeConfigurations."thorn@remote".activationPackage'
  #   ./result/activate
  flake.homeConfigurations."thorn@remote" = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    # nixvim/lsp.nix reads networking.hostName; there is no NixOS system
    # behind this profile.
    extraSpecialArgs.osConfig = {
      networking.hostName = "remote";
    };

    modules = [
      inputs.stylix.homeModules.stylix
      config.homeManager.modules.nixvim

      {
        home.username = "thorn";
        home.homeDirectory = "/home/thorn";
        home.stateVersion = "26.11";

        # nixvim/core.nix enables stylix.targets.nixvim; needs stylix on.
        stylix = {
          enable = true;
          base16Scheme = "${inputs.self}/assets/catppuccin-mocha.yaml";
        };
      }
    ];
  };
}
