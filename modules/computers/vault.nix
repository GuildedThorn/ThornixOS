{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/vault/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/vault/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.vault = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-vaultwarden
      config.nixos.modules.services-thorncloud-acme
      "${inputs.self}/hosts/vault/disko.nix"
      "${inputs.self}/hosts/vault/networking.nix"

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
