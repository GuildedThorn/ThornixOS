{ config, inputs, ... }:
{
  flake.nixosConfigurations.mac = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      config.nixos.modules.base
      config.nixos.modules.home-manager-base
      config.nixos.modules.thorn-user

      config.nixos.modules."desktop-hyprland"
      config.nixos.modules."processor-intel"
      config.nixos.modules."graphics-amd"

      config.nixos.modules."services-clamav"
      config.nixos.modules."services-proxmox"
      config.nixos.modules."services-ssh"

      ../../hosts/mac/disko.nix
      ../../hosts/mac/networking.nix
    ];
  };
}
