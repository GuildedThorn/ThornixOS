{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/codex/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.codex = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-codex
      config.nixos.modules.services-thorncloud-acme
      config.nixos.modules.services-ssh

      config.nixos.modules.hardware-qemu-guest
      "${inputs.self}/hosts/codex/disko.nix"
      "${inputs.self}/hosts/codex/networking.nix"

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
    ];
  };
}
