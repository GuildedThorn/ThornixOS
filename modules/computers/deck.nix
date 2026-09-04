{ config, inputs, ... }:
{
  flake.nixosConfigurations.deck = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-interactive
      inputs.jovian-nixos.nixosModules.jovian

      config.nixos.modules.desktop-kde-wle
      config.nixos.modules.services-audio
      config.nixos.modules.services-bluetooth
      config.nixos.modules.services-ssh

      { _module.args.inputs = inputs; }
      "${inputs.self}/hosts/deck/disko.nix"
      "${inputs.self}/hosts/deck/networking.nix"
      "${inputs.self}/hosts/deck/system.nix"
      { home-manager.users.thorn = import "${inputs.self}/hosts/deck/home.nix"; }
    ];
  };
}
