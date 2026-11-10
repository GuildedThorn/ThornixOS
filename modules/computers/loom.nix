{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/loom/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/loom/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.loom = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).loom.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-n8n-loom
      config.nixos.modules.services-thorncloud-acme
      ../../hosts/loom/disko.nix
      ../../hosts/loom/networking.nix

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
