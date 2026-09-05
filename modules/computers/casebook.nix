{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/casebook/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/casebook/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.casebook = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-thehive
      config.nixos.modules.services-thorncloud-acme
      "${inputs.self}/hosts/casebook/disko.nix"
      "${inputs.self}/hosts/casebook/networking.nix"

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
