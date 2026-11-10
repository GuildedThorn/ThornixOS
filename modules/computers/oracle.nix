{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/oracle/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/oracle/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.oracle = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { _module.args.inputs = inputs; }
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).oracle.system; }

      config.nixos.modules.profile-qemu-server

      ../../hosts/oracle/opencti
      config.nixos.modules.services-thorncloud-acme
      ../../hosts/oracle/disko.nix
      ../../hosts/oracle/networking.nix

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
