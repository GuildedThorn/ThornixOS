{ config, inputs, ... }:
{
  flake.nixosConfigurations.vmware-guest = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      config.nixos.modules.base
      config.nixos.modules.home-manager-base
      config.nixos.modules.thorn-user

      config.nixos.modules."desktop-xfce-i3"

      config.nixos.modules."services-audio"
      config.nixos.modules."services-clamav"
      config.nixos.modules."services-ssh"

      ../../hosts/vmware-guest/networking.nix

      { home-manager.users.thorn = import ../../hosts/vmware-guest/home.nix; }
    ];
  };
}
