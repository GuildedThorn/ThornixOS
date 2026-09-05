{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/herald/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/herald/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.herald = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-herald
      config.nixos.modules.services-thorncloud-acme
      "${inputs.self}/hosts/herald/disko.nix"
      "${inputs.self}/hosts/herald/networking.nix"

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
