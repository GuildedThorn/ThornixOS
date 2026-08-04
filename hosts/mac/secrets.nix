{
  config,
  lib,
  pkgs,
  ...
}:
let
  proxmoxCertificate = ../../certs/proxmox.guildedthorn.arpa.crt;
  proxmoxPrivateKey = config.sops.secrets.proxmox_tls_key;
in
{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  thorn.telemetry.enable = true;

  # Private key for the Proxmox web panel's custom TLS certificate.
  sops.secrets.proxmox_tls_key = {
    owner = "root";
    group = "www-data";
    mode = "0440";
  };

  # Use Proxmox's own certificate installer so the certificate/key pair is
  # validated before the existing custom certificate is replaced.
  systemd.services.proxmox-tls-certificate = {
    description = "Install the Proxmox web-panel TLS certificate";
    wantedBy = [ "multi-user.target" ];
    wants = [ "pve-cluster.service" ];
    after = [ "pve-cluster.service" ];
    before = [ "pveproxy.service" ];
    restartTriggers = [
      proxmoxCertificate
      proxmoxPrivateKey.sopsFile
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.proxmox-ve}/bin/pvenode cert set \
        ${lib.escapeShellArg proxmoxCertificate} \
        ${lib.escapeShellArg proxmoxPrivateKey.path} \
        --force
    '';
  };

  # Reinstall first and then restart the proxy whenever either half changes.
  systemd.services.pveproxy = {
    wants = [ "proxmox-tls-certificate.service" ];
    after = [ "proxmox-tls-certificate.service" ];
    restartTriggers = [
      proxmoxCertificate
      proxmoxPrivateKey.sopsFile
    ];
  };
}
