{ config, inputs, ... }:
{
  flake.nixosConfigurations.viewfinder = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).viewfinder.system; }

      config.nixos.modules.thorn-interactive
      inputs.sc0710.nixosModules.default
      config.nixos.modules.hardware-sc0710-firmware
      config.nixos.modules.hardware-sc0710-signed
      { _module.args.sc0710Src = inputs.sc0710; }

      config.nixos.modules.desktop-hyprland
      config.nixos.modules.processor-amd
      config.nixos.modules.graphics-nvidia

      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-capture-card
      config.nixos.modules.services-clamav
      config.nixos.modules.services-flare-agent
      config.nixos.modules.services-flare-lab
      config.nixos.modules.services-hashtopolis-agent
      config.nixos.modules.services-obs
      config.nixos.modules.services-proxmox
      config.nixos.modules.services-spicetify
      config.nixos.modules.services-ssh
      config.nixos.modules.services-zeek

      config.nixos.modules.hardware-viewfinder
      ../../hosts/viewfinder/disko.nix
      ../../hosts/viewfinder/flare-lab.nix
      ../../hosts/viewfinder/networking.nix
      ../../hosts/viewfinder/secrets.nix

      { home-manager.users.thorn = import ../../hosts/viewfinder/home.nix; }

      ../../hosts/viewfinder/system.nix
    ];
  };
}
