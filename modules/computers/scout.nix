{ config, inputs, ... }:
{
  flake.nixosConfigurations.scout = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).scout.system; }

      config.nixos.modules.thorn-interactive
      inputs.hjem.nixosModules.default

      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-intel
      config.nixos.modules.desktop-hyprland

      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-clamav
      config.nixos.modules.services-displaylink
      config.nixos.modules.services-fingerprint
      config.nixos.modules.services-obs
      config.nixos.modules.services-observability-roaming
      config.nixos.modules.services-spicetify
      config.nixos.modules.services-sdr
      config.nixos.modules.services-ssh

      config.nixos.modules.thorn-glance

      config.nixos.modules.hardware-scout
      ../../hosts/scout/networking.nix
      ../../hosts/scout/secrets.nix
      ../../hosts/scout/wireguard.nix

      { home-manager.users.thorn = import ../../hosts/scout/home.nix; }

      { _module.args.inputs = inputs; }
      ../../hosts/scout/system.nix
    ];
  };
}
