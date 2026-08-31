{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/resolver/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.resolver = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core
      config.nixos.modules.services-ssh
      config.nixos.modules.services-thorncloud-acme

      config.nixos.modules.hardware-qemu-guest
      "${inputs.self}/hosts/resolver/disko.nix"
      "${inputs.self}/hosts/resolver/networking.nix"

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

          services.technitium-dns-server = {
            enable = true;
            openFirewall = false;
          };

          thorn.acme = {
            enable = true;
            domain = "resolver.guildedthorn.arpa";
          };

          services.nginx = {
            enable = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;
            virtualHosts."resolver.guildedthorn.arpa" = {
              serverName = "resolver.guildedthorn.arpa";
              forceSSL = true;
              useACMEHost = "resolver.guildedthorn.arpa";
              locations."/" = {
                proxyPass = "http://127.0.0.1:5380";
                proxyWebsockets = true;
              };
            };
          };

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
