{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/lure/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/lure/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.lure = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-opencanary
      "${inputs.self}/hosts/lure/disko.nix"
      "${inputs.self}/hosts/lure/networking.nix"

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
