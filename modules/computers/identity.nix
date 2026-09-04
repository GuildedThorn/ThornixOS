{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/identity/admin-ssh-keys.nix;
  identityCertificate = "${inputs.self}/certs/identity.guildedthorn.arpa.crt";
in
{
  flake.nixosConfigurations.identity = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-headless

      config.nixos.modules.services-authentik
      config.nixos.modules.services-ssh

      config.nixos.modules.hardware-qemu-guest
      "${inputs.self}/hosts/identity/disko.nix"
      "${inputs.self}/hosts/identity/networking.nix"
      "${inputs.self}/hosts/identity/secrets.nix"

      (
        { config, lib, ... }:
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

          # Nginx is the sole network-facing Authentik listener. Authentik's
          # HTTP backend and generated-certificate HTTPS listener stay on
          # loopback; the ThornCloud_CA leaf key is available only to nginx.
          services.nginx = {
            enable = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;
            virtualHosts."identity.guildedthorn.arpa" = {
              serverName = "identity.guildedthorn.arpa";
              onlySSL = true;
              listen = [
                {
                  addr = "0.0.0.0";
                  port = 443;
                  ssl = true;
                }
              ];
              sslCertificate = identityCertificate;
              sslCertificateKey = config.sops.secrets.authentik_tls_key.path;
              extraConfig = ''
                add_header Strict-Transport-Security "max-age=31536000" always;
              '';
              locations."/" = {
                proxyPass = "http://127.0.0.1:9000";
                proxyWebsockets = true;
              };
            };
          };

          systemd.services.nginx = {
            wants = [ "authentik.service" ];
            after = [ "authentik.service" ];
          };

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
