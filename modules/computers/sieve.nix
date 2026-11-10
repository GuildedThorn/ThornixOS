{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/sieve/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/sieve/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.sieve = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).sieve.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-greenbone
      config.nixos.modules.services-thorncloud-acme
      ../../hosts/sieve/disko.nix
      ../../hosts/sieve/networking.nix

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
