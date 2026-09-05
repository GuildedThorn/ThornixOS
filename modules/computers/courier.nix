{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/courier/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/courier/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.courier = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-courier-mail
      "${inputs.self}/hosts/courier/disko.nix"
      "${inputs.self}/hosts/courier/networking.nix"

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
