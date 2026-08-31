{
  vmid = 118;
  address = "172.16.25.66";
  isoLabel = "THORNIX_RESOLVER";
  diskSerial = "THORNIX_DNS_118";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 2;
    memoryMiB = 4096;
    minimumMemoryMiB = 4096;
    diskGiB = 40;
  };

  readiness = {
    displayName = "Resolver";
    label = "Technitium DNS secondary";
    units = [ "technitium-dns-server.service" ];
    httpChecks = [
      {
        url = "https://resolver.guildedthorn.arpa/";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "resolver.guildedthorn.arpa:443:172.16.25.66";
      }
    ];
    readyLines = [
      "Technitium UI: https://resolver.guildedthorn.arpa/"
      "Change the default administrator password before enabling client DNS."
    ];
  };
}
