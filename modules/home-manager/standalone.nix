{ inputs, config, ... }:
let
  rice = import ../../lib/rice.nix;
in
{
  # Standalone Home Manager profile for applying this flake's thorn setup on a
  # machine without touching its NixOS config: clone this repo, then
  #   nix build '.#homeConfigurations."thorn@remote".activationPackage'
  #   ./result/activate
  flake.homeConfigurations."thorn@remote" = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    # thorn modules read osConfig (e.g. nixvim/lsp.nix wants
    # networking.hostName); there is no NixOS system behind this profile.
    extraSpecialArgs.osConfig = {
      networking.hostName = "remote";
    };

    modules = [
      inputs.stylix.homeModules.stylix
      config.homeManager.modules.thorn

      (
        { pkgs, ... }:
        {
          home.username = "thorn";
          home.homeDirectory = "/home/thorn";
          # base.nix sets nix.settings; HM asserts nix.package when no NixOS
          # system supplies one.
          nix.package = pkgs.nix;

          # On fleet hosts this half lives in modules/users/thorn.nix and is
          # propagated to HM by the stylix NixOS module; standalone needs it
          # directly (base.nix enables home.pointerCursor, stylix names it).
          stylix = {
            enable = true;
            base16Scheme = "${inputs.self}/assets/catppuccin-mocha.yaml";
            cursor = {
              inherit (rice.cursor) name size;
              package = pkgs.catppuccin-cursors.mochaMauve;
            };
            fonts = {
              sansSerif = {
                package = pkgs.geist-font;
                name = rice.fonts.sans;
              };
              serif = {
                package = pkgs.geist-font;
                name = rice.fonts.sans;
              };
              monospace = {
                package = pkgs.nerd-fonts.geist-mono;
                name = rice.fonts.mono;
              };
              emoji = {
                package = pkgs.noto-fonts-color-emoji;
                name = "Noto Color Emoji";
              };
            };
          };
        }
      )
    ];
  };
}
