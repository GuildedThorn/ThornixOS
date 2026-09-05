{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/forge/admin-ssh-keys.nix;
  secretsModule = "${inputs.self}/hosts/forge/secrets.nix";
  secretsReady = builtins.pathExists "${inputs.self}/hosts/forge/secrets.yaml";
  telemetryModule = "${inputs.self}/hosts/forge/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.forge = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-hydra-forge
      config.nixos.modules.services-thorncloud-acme
      "${inputs.self}/hosts/forge/disko.nix"
      "${inputs.self}/hosts/forge/networking.nix"

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
