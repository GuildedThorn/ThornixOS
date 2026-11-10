{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/herald/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/herald/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.herald = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).herald.system; }

      config.nixos.modules.profile-qemu-server

      ../../hosts/herald/notifications
      config.nixos.modules.services-thorncloud-acme
      ../../hosts/herald/disko.nix
      ../../hosts/herald/networking.nix

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
