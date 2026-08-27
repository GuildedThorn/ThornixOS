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

      config.nixos.modules.hardware-qemu-guest
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
          programs.nh.clean.dates = "daily";

          # Pixie has a deliberately small system disk and its audit events
          # are low-value once they age out of the local incident window.
          # Keep local observability bounded instead of letting it compete
          # with the embedded rescue closure in /nix/store.
          security.auditd.settings = {
            max_log_file = 25;
            num_logs = 8;
          };
          services.journald.extraConfig = ''
            SystemMaxUse=256M
            RuntimeMaxUse=64M
            MaxRetentionSec=3day
          '';

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
