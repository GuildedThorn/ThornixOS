{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/casebook/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/casebook/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.casebook = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { _module.args.inputs = inputs; }
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).casebook.system; }

      config.nixos.modules.profile-qemu-server

      ../../hosts/casebook/thehive
      config.nixos.modules.services-thorncloud-acme
      ../../hosts/casebook/disko.nix
      ../../hosts/casebook/networking.nix

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
