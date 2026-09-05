{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/codex/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.codex = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-codex
      config.nixos.modules.services-thorncloud-acme
      "${inputs.self}/hosts/codex/disko.nix"
      "${inputs.self}/hosts/codex/networking.nix"

      {
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ];
  };
}
