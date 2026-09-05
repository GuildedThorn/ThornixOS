{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/hound/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/hound/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.hound = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-velociraptor
      "${inputs.self}/hosts/hound/disko.nix"
      "${inputs.self}/hosts/hound/networking.nix"

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
