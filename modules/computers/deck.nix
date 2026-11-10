{ config, inputs, ... }:
{
  flake.nixosConfigurations.deck = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).deck.system; }

      config.nixos.modules.thorn-interactive
      inputs.jovian-nixos.nixosModules.jovian

      config.nixos.modules.desktop-kde-wle
      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-ssh

      { _module.args.inputs = inputs; }
      ../../hosts/deck/disko.nix
      ../../hosts/deck/networking.nix
      ../../hosts/deck/system.nix
      { home-manager.users.thorn = import ../../hosts/deck/home.nix; }
      {
        services.blueman.enable = false;
        services.flatpak.enable = true;
      }
    ];
  };
}
