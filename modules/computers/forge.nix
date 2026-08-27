{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/forge/admin-ssh-keys.nix;
  secretsModule = "${inputs.self}/hosts/forge/secrets.nix";
  secretsReady = builtins.pathExists "${inputs.self}/hosts/forge/secrets.yaml";
  telemetryModule = "${inputs.self}/hosts/forge/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.forge = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-hydra-forge
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-ssh

      config.nixos.modules.hardware-qemu-guest
      "${inputs.self}/hosts/forge/disko.nix"
      "${inputs.self}/hosts/forge/networking.nix"

      (
        { lib, ... }:
        {
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
    ++ inputs.nixpkgs.lib.optional secretsReady secretsModule
    ++ inputs.nixpkgs.lib.optionals telemetryReady [
      config.nixos.modules.services-canary
      telemetryModule
    ];
  };
}
