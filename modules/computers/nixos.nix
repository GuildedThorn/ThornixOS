{ config, inputs, ... }:
{
  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).nixos.system; }

      config.nixos.modules.thorn-interactive
      inputs.hjem.nixosModules.default

      config.nixos.modules.desktop-hyprland
      config.nixos.modules.processor-amd
      config.nixos.modules.graphics-amd

      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-clamav
      config.nixos.modules.services-crowdsec
      config.nixos.modules.services-displaylink
      config.nixos.modules.services-fingerprint
      config.nixos.modules.services-hashtopolis-agent
      config.nixos.modules.services-ollama
      config.nixos.modules.services-retroarch
      config.nixos.modules.services-spicetify
      config.nixos.modules.services-sdr
      config.nixos.modules.services-ssh
      config.nixos.modules.services-steam
      config.nixos.modules.services-steam-frame
      config.nixos.modules.services-tablets
      config.nixos.modules.services-velociraptor-client
      config.nixos.modules.services-vr

      config.nixos.modules.services-security-tools

      config.nixos.modules.thorn-glance

      config.nixos.modules.hardware-nixos
      ../../hosts/nixos/disko.nix
      ../../hosts/nixos/networking.nix
      ../../hosts/nixos/nfs.nix
      ../../hosts/nixos/secrets.nix

      { home-manager.users.thorn = import ../../hosts/nixos/home.nix; }

      { _module.args.inputs = inputs; }
      ../../hosts/nixos/system.nix
    ];
  };
}
