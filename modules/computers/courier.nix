{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/courier/admin-ssh-keys.nix;
  telemetryModule = "${inputs.self}/hosts/courier/telemetry.nix";
  telemetryReady = builtins.pathExists telemetryModule;
in
{
  flake.nixosConfigurations.courier = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-courier-mail
      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/courier/hardware-configuration.nix"
      "${inputs.self}/hosts/courier/disko.nix"
      "${inputs.self}/hosts/courier/networking.nix"

      (
        { lib, ... }:
        {
          # Mail contents and administrative changes are sensitive enough to
          # justify complete service-exec auditing on this headless VM.
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
