{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/resolver/admin-ssh-keys.nix;
in
{
  flake.nixosConfigurations.resolver = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-headless
      config.nixos.modules.services-ssh
      config.nixos.modules.services-thorncloud-acme

      config.nixos.modules.hardware-qemu-guest
      "${inputs.self}/hosts/resolver/disko.nix"
      "${inputs.self}/hosts/resolver/networking.nix"
      "${inputs.self}/hosts/shared/technitium-config.nix"

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
                extraConfig = ''
                  allow 172.16.25.3;
                  allow 192.168.1.6;
                  allow 10.10.10.4;
                  deny all;
                '';
              };
              locations."= /dns-query" = {
                proxyPass = "http://127.0.0.1:8053/dns-query";
                extraConfig = ''
                  proxy_set_header X-Real-IP $remote_addr;
                  allow 172.16.25.0/24;
                  allow 192.168.1.0/24;
                  allow 10.10.10.0/24;
                  deny all;
                '';
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
