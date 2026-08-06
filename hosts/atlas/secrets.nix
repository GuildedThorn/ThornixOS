{ config, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;

  # Only nginx terminates TLS. Keep the private key unreadable by NetBox,
  # PostgreSQL, Redis, and every interactive account.
  sops.secrets.netbox_tls_key = {
    owner = config.services.nginx.user;
    group = config.services.nginx.group;
    mode = "0400";
    restartUnits = [ "nginx.service" ];
  };
}
