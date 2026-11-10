{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/minebox/admin-ssh-keys.nix;
  telemetryModule = ../../hosts/minebox/telemetry.nix;
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.minebox = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).minebox.system; }

      config.nixos.modules.thorn-headless

      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-intel

      config.nixos.modules.services-ssh

      config.nixos.modules.mc-cluster
      ../../hosts/minebox/mc-cluster.nix

      config.nixos.modules.mc-lobby
      ../../hosts/minebox/mc-lobby.nix

      config.nixos.modules.hardware-minebox
      ../../hosts/minebox/disko.nix
      ../../hosts/minebox/networking.nix

      (
        { ... }:
        {
          thorn.audit.execScope = "all";

          boot.loader.grub = {
            enable = true;
            devices = [ "/dev/sda" ];
            efiSupport = false;
          };

          users.users.root.initialHashedPassword = "!";
          users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
        }
      )
    ]
    ++ inputs.nixpkgs.lib.optionals telemetryReady [
      config.nixos.modules.services-canary
      telemetryModule
    ];
  };
}
