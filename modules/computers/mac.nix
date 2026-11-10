{ config, inputs, ... }:
{
  flake.nixosConfigurations.mac = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).mac.system; }

      config.nixos.modules.thorn-interactive

      config.nixos.modules.desktop-xfce-i3
      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-amd

      config.nixos.modules.services-canary
      config.nixos.modules.services-clamav
      config.nixos.modules.services-ksm
      config.nixos.modules.services-proxmox
      config.nixos.modules.services-proxmox-provisioner
      config.nixos.modules.services-ssh
      config.nixos.modules.services-zeek

      ../../hosts/mac/disko.nix
      ../../hosts/mac/networking.nix
      ../../hosts/mac/secrets.nix

      { home-manager.users.thorn = import ../../hosts/mac/home.nix; }

      ../../hosts/mac/system.nix
    ];
  };
}
