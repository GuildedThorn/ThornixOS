{ inputs, ... }:
{
  flake.nixosConfigurations.voice-office = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).voice-office.system; }

      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

      { _module.args.inputs = inputs; }
      ../../hosts/voice-office/system.nix
    ];
  };
}
