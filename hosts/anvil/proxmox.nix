let
  caMaterialReady =
    builtins.pathExists ../../certs/anvil-intermediate.crt && builtins.pathExists ./secrets.yaml;
in
{
  vmid = 107;
  address = "172.16.25.55";
  isoLabel = "THORNIX_ANVIL";
  diskSerial = "THORNIX_ANVIL_107";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 2048;
    diskGiB = 20;
  };

  readiness =
    if caMaterialReady then
      {
        displayName = "Anvil";
        label = "Anvil internal certificate authority";
        units = [ "step-ca.service" ];
        httpChecks = [
          {
            url = "https://anvil.guildedthorn.arpa/health";
            caCertificate = ../../certs/ThornCloud_CA.crt;
            resolve = "anvil.guildedthorn.arpa:443:172.16.25.55";
            expectPattern = ''"status"[[:space:]]*:[[:space:]]*"ok"'';
          }
        ];
        readyLines = [
          "Anvil CA: https://anvil.guildedthorn.arpa/health"
          "ACME directory: https://anvil.guildedthorn.arpa/acme/thorncloud/directory"
        ];
      }
    else
      {
        displayName = "Anvil";
        label = "Anvil secure bootstrap host";
        readyLines = [
          "Anvil bootstrap host is ready at 172.16.25.55."
          "Capture its ed25519 host key, add its SOPS recipient, then create the issuing intermediate."
          "The ThornCloud root private key must remain offline and must never be copied to Anvil."
        ];
      };
}
