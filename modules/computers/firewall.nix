{ config, inputs, ... }:
{
  flake.nixosConfigurations.firewall = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core
    ];
  };
}
