{
  vmid = 117;
  address = "172.16.25.65";
  isoLabel = "THORNIX_VAULT";
  diskSerial = "THORNIX_VAULT_117";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 1;
    memoryMiB = 2048;
    diskGiB = 40;
  };

  readiness = {
    displayName = "Vault";
    label = "Vaultwarden password manager";
    timeoutSeconds = 1200;
    units = [
      "vaultwarden-admin-token.service"
      "vaultwarden.service"
      "nginx.service"
    ];
    httpChecks = [
      {
        url = "https://vault.guildedthorn.arpa/alive";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "vault.guildedthorn.arpa:443:172.16.25.65";
      }
    ];
    readyLines = [
      "Vaultwarden: https://vault.guildedthorn.arpa/"
      "Retrieve the initial admin token with 'vault-admin-token' as root."
      "Open https://vault.guildedthorn.arpa/admin, invite your account, and require two-step login."
    ];
  };
}
