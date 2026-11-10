{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/forge/admin-ssh-keys.nix;
  secretsModule = ../../hosts/forge/secrets.nix;
  secretsReady = builtins.pathExists "${inputs.self}/hosts/forge/secrets.yaml";
  telemetryModule = ../../hosts/forge/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.forge = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).forge.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-hydra-forge
      config.nixos.modules.services-thorncloud-acme
      ../../hosts/forge/disko.nix
      ../../hosts/forge/networking.nix

      {
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ]
    ++ inputs.nixpkgs.lib.optional secretsReady secretsModule
    ++ inputs.nixpkgs.lib.optionals telemetryReady [
      config.nixos.modules.services-canary
      telemetryModule
    ];
  };
}
