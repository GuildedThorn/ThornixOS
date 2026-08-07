{
  vmid = 111;
  address = "172.16.25.59";
  isoLabel = "THORNIX_CASEBOOK";
  diskSerial = "THORNIX_CASEBOOK_111";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 8;
    memoryMiB = 16384;
    diskGiB = 100;
  };

  readiness = {
    displayName = "Casebook";
    label = "Casebook TheHive incident-response platform";
    timeoutSeconds = 3600;
    units = [
      "docker.service"
      "casebook-thehive.service"
      "casebook-thehive-admin.service"
      "casebook-thehive-health.timer"
      "nginx.service"
    ];
    httpChecks = [
      {
        url = "https://casebook.guildedthorn.arpa/";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "casebook.guildedthorn.arpa:443:172.16.25.59";
      }
    ];
    readyLines = [
      "Casebook: https://casebook.guildedthorn.arpa/"
      "Read the generated one-time administrator password with:"
      "  ssh root@172.16.25.59 casebook-admin-password"
      "Add a pfSense host override for casebook.guildedthorn.arpa -> 172.16.25.59."
    ];
  };
}
