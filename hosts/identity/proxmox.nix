{
  vmid = 104;
  address = "172.16.25.52";
  isoLabel = "THORNIX_IDENTITY";
  diskSerial = "THORNIX_IDENTITY_104";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 4096;
    diskGiB = 40;
  };

  readiness = {
    displayName = "Identity";
    label = "Authentik HTTPS";
    units = [ "authentik.service" ];
    httpChecks = [
      {
        url = "https://identity.guildedthorn.arpa/";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "identity.guildedthorn.arpa:443:172.16.25.52";
      }
    ];
    readyLines = [
      "Complete Authentik first-time setup at:"
      "  https://identity.guildedthorn.arpa/if/flow/initial-setup/"
    ];
  };
}
