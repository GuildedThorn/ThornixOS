{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/sieve/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/sieve/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.sieve = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-greenbone
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/sieve/hardware-configuration.nix"
      "${inputs.self}/hosts/sieve/disko.nix"
      "${inputs.self}/hosts/sieve/networking.nix"

      (
        { lib, ... }:
        {
          # Scanner containers are Sieve's primary attack surface. Audit all
          # service execution, not only commands attached to login sessions.
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
