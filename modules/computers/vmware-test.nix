{ config, inputs, ... }:
{
  flake.nixosConfigurations.vmware-test = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.desktop-xfce-i3

      config.nixos.modules.services-audio
      config.nixos.modules.services-clamav
      config.nixos.modules.services-ssh

      "${inputs.self}/hosts/vmware-test/networking.nix"
    ];
  };
}
