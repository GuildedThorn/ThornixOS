{ config, inputs, ... }:
{
  flake.nixosConfigurations.firewall = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      config.nixos.modules.base
      config.nixos.modules.home-manager-base
      config.nixos.modules.thorn-user
    ];
  };
}
