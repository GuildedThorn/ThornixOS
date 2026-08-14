{
  vmid = 115;
  address = "172.16.25.63";
  isoLabel = "THORNIX_HERALD";
  diskSerial = "THORNIX_HERALD_115";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 1;
    memoryMiB = 2048;
    # A current NixOS closure plus one rollback generation no longer fits in
    # the original 20 GiB disk. Keep enough headroom for atomic upgrades and
    # garbage collection instead of relying on emergency store deletion.
    diskGiB = 40;
  };

  readiness = {
    displayName = "Herald";
    label = "Herald ntfy notification router";
    timeoutSeconds = 1200;
    units = [
      "herald-ntfy-admin.service"
      "ntfy-sh.service"
      "nginx.service"
    ];
    httpChecks = [
      {
        url = "https://herald.guildedthorn.arpa/v1/health";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "herald.guildedthorn.arpa:443:172.16.25.63";
        expectPattern = "healthy.*true";
      }
    ];
    readyLines = [
      "Herald: https://herald.guildedthorn.arpa/"
      "Add a pfSense host override for herald.guildedthorn.arpa -> 172.16.25.63."
      "Run 'herald-initial-password' as root, log in as thorn, and change the generated password."
      "SMTP-to-topic: send to ntfy-TOPIC+TOKEN@herald.guildedthorn.arpa through 172.16.25.63:25."
    ];
  };
}
