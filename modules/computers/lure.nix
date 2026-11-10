{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/lure/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/lure/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.lure = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).lure.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-opencanary
      ../../hosts/lure/disko.nix
      ../../hosts/lure/networking.nix

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
