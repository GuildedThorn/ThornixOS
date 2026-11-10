{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/atlas/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.atlas = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).atlas.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-canary
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-netbox
      ../../hosts/atlas/disko.nix
      ../../hosts/atlas/networking.nix
      ../../hosts/atlas/secrets.nix

      {
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ];
  };
}
