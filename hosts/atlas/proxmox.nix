{
  vmid = 106;
  address = "172.16.25.54";
  isoLabel = "THORNIX_ATLAS";
  diskSerial = "THORNIX_ATLAS_106";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 4096;
    diskGiB = 40;
  };

  readiness = {
    displayName = "Atlas";
    label = "Atlas NetBox stack";
    units = [
      "netbox.service"
      "netbox-rq.service"
      "nginx.service"
      "postgresql.service"
      "redis-netbox.service"
    ];
    httpChecks = [
      {
        url = "https://atlas.guildedthorn.arpa/login/";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "atlas.guildedthorn.arpa:443:172.16.25.54";
      }
    ];
    readyLines = [
      "Atlas: https://atlas.guildedthorn.arpa/"
      "Create the first local administrator with:"
      "  ssh -t root@172.16.25.54 netbox-manage createsuperuser"
    ];
  };
}
