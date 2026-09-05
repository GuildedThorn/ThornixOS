{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/sieve/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/sieve/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.sieve = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-greenbone
      config.nixos.modules.services-thorncloud-acme
      "${inputs.self}/hosts/sieve/disko.nix"
      "${inputs.self}/hosts/sieve/networking.nix"

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
