{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/atlas/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.atlas = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-canary
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-netbox
      config.nixos.modules.services-ssh

      config.nixos.modules.hardware-qemu-guest
      "${inputs.self}/hosts/atlas/disko.nix"
      "${inputs.self}/hosts/atlas/networking.nix"
      "${inputs.self}/hosts/atlas/secrets.nix"

      (
        { lib, ... }:
        {
          # Atlas is headless and service processes are its primary attack
          # surface, so audit every execution rather than login sessions only.
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
            settings = {
              KbdInteractiveAuthentication = false;
              PasswordAuthentication = false;
              PermitRootLogin = "prohibit-password";
            };
          };
          users.users.root = {
            initialHashedPassword = "!";
            openssh.authorizedKeys.keys = adminSshKeys;
          };
        }
      )
    ];
  };
}
