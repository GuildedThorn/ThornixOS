{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/thornbot/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/thornbot/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.thornbot = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).thornbot.system; }

      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-ssh
      config.nixos.modules.services-thornbot
      ../../hosts/thornbot/disko.nix
      ../../hosts/thornbot/networking.nix
      ../../hosts/thornbot/secrets.nix

      {
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
        services.thornbot.enable = true;
      }
    ]
    ++ inputs.nixpkgs.lib.optionals telemetryReady [
      config.nixos.modules.services-canary
      telemetryModule
    ];
  };
}
