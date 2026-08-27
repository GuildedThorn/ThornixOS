{ config, inputs, ... }:
{
  flake.nixosConfigurations.vmware-guest = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.desktop-xfce-i3

      config.nixos.modules.services-audio
      config.nixos.modules.services-clamav
      config.nixos.modules.services-ssh
      config.nixos.modules.services-vmware-guest

      config.nixos.modules.hardware-bios-placeholder
      "${inputs.self}/hosts/vmware-guest/networking.nix"

      { home-manager.users.thorn = import "${inputs.self}/hosts/vmware-guest/home.nix"; }
    ];
  };
}
