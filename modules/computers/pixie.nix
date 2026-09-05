{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/pixie/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.pixie = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-pixie-netboot
      "${inputs.self}/hosts/pixie/disko.nix"
      "${inputs.self}/hosts/pixie/networking.nix"

      {
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

        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ];
  };
}
