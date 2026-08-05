{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/identity/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.identity = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-authentik
      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/identity/hardware-configuration.nix"
      "${inputs.self}/hosts/identity/disko.nix"
      "${inputs.self}/hosts/identity/networking.nix"

      (
        { lib, ... }:
        {
          # This headless identity provider needs visibility into service
          # executions as well as interactive sessions.
          thorn.audit.execScope = "all";

          security.pki.certificates = [
            (builtins.readFile "${inputs.self}/certs/ThornCloud_CA.crt")
          ];

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
              PermitRootLogin = "prohibit-password";
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
            };
          };

          # Key-only break-glass access remains independent of Authentik.
          users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
        }
      )
    ];
  };
}
