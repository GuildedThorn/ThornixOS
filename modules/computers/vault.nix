{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/vault/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/vault/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.vault = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).vault.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-vaultwarden
      config.nixos.modules.services-thorncloud-acme
      ../../hosts/vault/disko.nix
      ../../hosts/vault/networking.nix

      {
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ]
    ++ inputs.nixpkgs.lib.optionals telemetryReady [
      config.nixos.modules.services-canary
      telemetryModule
    ];
  };
}
