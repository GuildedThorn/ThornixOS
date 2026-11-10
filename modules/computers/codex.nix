{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/codex/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.codex = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).codex.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-codex
      config.nixos.modules.services-thorncloud-acme
      ../../hosts/codex/disko.nix
      ../../hosts/codex/networking.nix

      {
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ];
  };
}
