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
      config.nixos.modules.thorn-core

      config.nixos.modules.services-opencanary
      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/lure/hardware-configuration.nix"
      "${inputs.self}/hosts/lure/disko.nix"
      "${inputs.self}/hosts/lure/networking.nix"

      (
        { lib, ... }:
        {
          # A honeypot is useful only when local administrative activity is
          # distinguishable from an intruder touching a decoy service.
          thorn.audit.execScope = "all";

          boot = {
            growPartition = true;
            loader.grub = {
              enable = true;
              devices = lib.mkForce [ "/dev/sda" ];
              efiSupport = false;
            };
            kernelParams = [ "net.ifnames=0" ];
          };

          fileSystems."/".autoResize = true;
          services.qemuGuest.enable = true;

          services.openssh = {
            enable = true;
            openFirewall = false;
            settings = {
              AllowUsers = [ "root" ];
              KbdInteractiveAuthentication = false;
              PasswordAuthentication = false;
              PermitRootLogin = "prohibit-password";
              X11Forwarding = false;
            };
          };
          users.users.root = {
            initialHashedPassword = "!";
            openssh.authorizedKeys.keys = adminSshKeys;
          };
        }
      )
    ]
    ++ inputs.nixpkgs.lib.optionals telemetryReady [
      config.nixos.modules.services-canary
      telemetryModule
    ];
  };
}
