{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/identity/admin-ssh-keys.nix;
  identityCertificate = "${inputs.self}/certs/identity.guildedthorn.arpa.crt";
in
{
  flake.nixosConfigurations.identity = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-authentik
      "${inputs.self}/hosts/identity/disko.nix"
      "${inputs.self}/hosts/identity/networking.nix"
      "${inputs.self}/hosts/identity/secrets.nix"

      (
        { config, ... }:
        {
          security.pki.certificates = [
            (builtins.readFile "${inputs.self}/certs/ThornCloud_CA.crt")
          ];

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

          # Key-only break-glass access remains independent of Authentik.
          users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
        }
      )
    ];
  };
}
