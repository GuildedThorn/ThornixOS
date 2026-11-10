{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/courier/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/courier/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.courier = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).courier.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-courier-mail
      ../../hosts/courier/disko.nix
      ../../hosts/courier/networking.nix

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
