{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/identity/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.granite = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-headless
      config.nixos.modules.services-ssh
      config.nixos.modules.services-forgejo
      config.nixos.modules.services-jellyfin
      config.nixos.modules.services-seaweedfs
      config.nixos.modules.services-mongodb
      config.nixos.modules.services-immich
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.hardware-nixos

      "${inputs.self}/hosts/granite/disko.nix"
      "${inputs.self}/hosts/granite/networking.nix"
      "${inputs.self}/hosts/granite/nfs.nix"
      "${inputs.self}/hosts/granite/storage.nix"
      "${inputs.self}/hosts/granite/monitoring.nix"
      "${inputs.self}/hosts/granite/telemetry.nix"

      {
        # Keep the break-glass path available during the OS replacement.
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ];
  };
}
