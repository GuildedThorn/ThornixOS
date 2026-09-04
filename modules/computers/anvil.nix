{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/anvil/admin-ssh-keys.nix;
  caMaterialReady =
    builtins.pathExists "${inputs.self}/certs/anvil-intermediate.crt"
    && builtins.pathExists "${inputs.self}/hosts/anvil/secrets.yaml";
in
{
  flake.nixosConfigurations.anvil = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-headless

      config.nixos.modules.services-anvil-ca
      config.nixos.modules.services-canary
      config.nixos.modules.services-ssh

      config.nixos.modules.hardware-qemu-guest
      "${inputs.self}/hosts/anvil/disko.nix"
      "${inputs.self}/hosts/anvil/networking.nix"

      (
        { lib, ... }:
        {
          # Anvil is a headless trust service; audit service execution as well
          # as interactive sessions and leave no password authentication path.
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
    ++ inputs.nixpkgs.lib.optional caMaterialReady "${inputs.self}/hosts/anvil/secrets.nix";
  };
}
