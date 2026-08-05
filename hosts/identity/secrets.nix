{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # NixOS runs nginx as its dedicated unprivileged account with only the
  # capability needed to bind :443. Keep the key unavailable to Authentik
  # and every other service account.
  sops.secrets.authentik_tls_key = {
    owner = config.services.nginx.user;
    group = config.services.nginx.group;
    mode = "0400";
    restartUnits = [ "nginx.service" ];
  };
}
