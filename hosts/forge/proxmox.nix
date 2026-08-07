{
  vmid = 113;
  address = "172.16.25.61";
  isoLabel = "THORNIX_FORGE";
  diskSerial = "THORNIX_FORGE_113";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 8;
    memoryMiB = 16384;
    diskGiB = 200;
  };

  readiness = {
    displayName = "Forge";
    label = "Forge Hydra continuous-integration service";
    timeoutSeconds = 1800;
    units = [
      "hydra-evaluator.service"
      "hydra-queue-runner.service"
      "hydra-server.service"
      "nginx.service"
      "postgresql.service"
    ];
    httpChecks = [
      {
        url = "https://forge.guildedthorn.arpa/";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "forge.guildedthorn.arpa:443:172.16.25.61";
      }
    ];
    readyLines = [
      "Forge: https://forge.guildedthorn.arpa/"
      "Create the first Hydra administrator with:"
      "  ssh -t root@172.16.25.61 'sudo -u hydra hydra-create-user thorn --full-name Thorn --email-address admin@guildedthorn.com --password-prompt --role admin'"
      "Then create the ThornixOS project and main flake jobset as documented in README.md."
    ];
  };
}
