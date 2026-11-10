{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/hound/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/hound/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.hound = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { _module.args.inputs = inputs; }
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).hound.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-thorncloud-acme
      ../../hosts/hound/velociraptor
      ../../hosts/hound/disko.nix
      ../../hosts/hound/networking.nix

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
