{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/atlas/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.atlas = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-canary
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-netbox
      "${inputs.self}/hosts/atlas/disko.nix"
      "${inputs.self}/hosts/atlas/networking.nix"
      "${inputs.self}/hosts/atlas/secrets.nix"

      {
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ];
  };
}
