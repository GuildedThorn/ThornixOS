{ config, inputs, ... }:
{
  flake.nixosConfigurations.mitm = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core
      config.nixos.modules.services-ssh
      config.nixos.modules.services-thorncloud-acme

      config.nixos.modules.hardware-mitm
      { _module.args.inputs = inputs; }
      "${inputs.self}/hosts/mitm/disko.nix"
      "${inputs.self}/hosts/mitm/networking.nix"
      "${inputs.self}/hosts/mitm/system.nix"
      "${inputs.self}/hosts/mitm/casita-component.nix"
    ];
  };
}
