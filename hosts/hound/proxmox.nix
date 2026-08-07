{
  vmid = 109;
  address = "172.16.25.57";
  isoLabel = "THORNIX_HOUND";
  diskSerial = "THORNIX_HOUND_109";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 4;
    memoryMiB = 8192;
    diskGiB = 80;
  };

  readiness = {
    displayName = "Hound";
    label = "Hound Velociraptor endpoint visibility server";
    timeoutSeconds = 1800;
    units = [
      "hound-velociraptor-bootstrap.service"
      "velociraptor-server.service"
      "nginx.service"
    ];
    httpChecks = [
      {
        url = "https://hound.guildedthorn.arpa/app/index.html";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "hound.guildedthorn.arpa:443:172.16.25.57";
      }
    ];
    readyLines = [
      "Hound: https://hound.guildedthorn.arpa/"
      "Read the generated one-time administrator password with:"
      "  ssh root@172.16.25.57 hound-admin-password"
      "Add a pfSense host override for hound.guildedthorn.arpa -> 172.16.25.57."
    ];
  };
}
