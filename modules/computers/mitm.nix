{ config, inputs, ... }:
{
  flake.nixosConfigurations.mitm = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).mitm.system; }

      config.nixos.modules.thorn-headless
      config.nixos.modules.services-ssh
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-hashtopolis-server
      config.nixos.modules.services-threadfin

      config.nixos.modules.hardware-mitm
      { _module.args.inputs = inputs; }
      ../../hosts/mitm/disko.nix
      ../../hosts/mitm/networking.nix
      ../../hosts/mitm/system.nix
      ../../hosts/mitm/secrets.nix
      ../../hosts/mitm/casita-component.nix
      ../../hosts/shared/technitium-config.nix
    ];
  };
}
