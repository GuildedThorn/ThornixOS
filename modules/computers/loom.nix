{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/loom/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/loom/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.loom = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-n8n-loom
      config.nixos.modules.services-thorncloud-acme
      "${inputs.self}/hosts/loom/disko.nix"
      "${inputs.self}/hosts/loom/networking.nix"

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
