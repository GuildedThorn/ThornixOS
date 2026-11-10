{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/identity/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.granite = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).granite.system; }

      config.nixos.modules.thorn-headless
      config.nixos.modules.services-ssh
      ../../hosts/granite/forgejo
      ../../hosts/granite/reposilite
      ../../hosts/granite/jellyfin
      ../../hosts/granite/seaweedfs
      ../../hosts/granite/mongodb
      ../../hosts/granite/immich
      ../../hosts/granite/media-arr
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.hardware-nixos

      ../../hosts/granite/disko.nix
      ../../hosts/granite/networking.nix
      ../../hosts/granite/nfs.nix
      ../../hosts/granite/storage.nix
      ../../hosts/granite/monitoring.nix
      ../../hosts/granite/telemetry.nix

      {
        # Keep the break-glass path available during the OS replacement.
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ];
  };
}
