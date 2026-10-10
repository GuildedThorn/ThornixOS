{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/minebox/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/minebox/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.minebox = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-headless

      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-intel

      config.nixos.modules.services-ssh

      config.nixos.modules.mc-cluster
      "${inputs.self}/hosts/minebox/mc-cluster.nix"

      config.nixos.modules.hardware-minebox
      "${inputs.self}/hosts/minebox/disko.nix"
      "${inputs.self}/hosts/minebox/networking.nix"

      (
        { ... }:
        {
          thorn.audit.execScope = "all";

          boot.loader.grub = {
            enable = true;
            devices = [ "/dev/sda" ];
            efiSupport = false;
          };
          boot.initrd.systemd.enable = true;

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
