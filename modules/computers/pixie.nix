{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/pixie/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.pixie = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-pixie-netboot
      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/pixie/hardware-configuration.nix"
      "${inputs.self}/hosts/pixie/disko.nix"
      "${inputs.self}/hosts/pixie/networking.nix"

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
