{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/oracle/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/oracle/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.oracle = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-opencti
      config.nixos.modules.services-thorncloud-acme
      "${inputs.self}/hosts/oracle/disko.nix"
      "${inputs.self}/hosts/oracle/networking.nix"

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
