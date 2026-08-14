{
  vmid = 108;
  address = "172.16.25.56";
  isoLabel = "THORNIX_SIEVE";
  diskSerial = "THORNIX_SIEVE_108";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 4;
    memoryMiB = 8192;
    # Greenbone's feed images, SCAP data, and PostgreSQL state need roughly
    # 50 GiB before update headroom. The original 60 GiB disk filled during a
    # feed refresh and took PostgreSQL, ACME, logrotate, and Home Manager down
    # together. Match the live VM's expanded capacity.
    diskGiB = 120;
  };

  readiness = {
    displayName = "Sieve";
    label = "Sieve Greenbone vulnerability-management stack";
    # First boot downloads the scanner and Community Feed images. Give a slow
    # registry or initial feed import room to finish without weakening any of
    # the provisioner's identity and disk-safety checks.
    timeoutSeconds = 3600;
    units = [
      "docker.service"
      "sieve-greenbone.service"
      "sieve-greenbone-admin.service"
      "sieve-greenbone-health.timer"
      "nginx.service"
    ];
    httpChecks = [
      {
        url = "https://sieve.guildedthorn.arpa/";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "sieve.guildedthorn.arpa:443:172.16.25.56";
      }
    ];
    readyLines = [
      "Sieve: https://sieve.guildedthorn.arpa/"
      "Read the generated one-time administrator password with:"
      "  ssh root@172.16.25.56 sieve-admin-password"
      "Add a pfSense host override for sieve.guildedthorn.arpa -> 172.16.25.56."
    ];
  };
}
