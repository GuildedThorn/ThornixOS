{
  vmid = 112;
  address = "172.16.25.60";
  isoLabel = "THORNIX_ORACLE";
  diskSerial = "THORNIX_ORACLE_112";
  adminSshKeys = import ./admin-ssh-keys.nix;

  resources = {
    cores = 8;
    memoryMiB = 24576;
    # OpenCTI's measured working set is roughly 9 GiB. A 16 GiB floor leaves
    # service-growth headroom while returning idle cache to the hypervisor.
    minimumMemoryMiB = 16384;
    diskGiB = 150;
  };

  readiness = {
    displayName = "Oracle";
    label = "Oracle OpenCTI threat-intelligence platform";
    timeoutSeconds = 7200;
    units = [
      "docker.service"
      "oracle-opencti.service"
      "oracle-opencti-health.timer"
      "nginx.service"
    ];
    httpChecks = [
      {
        url = "https://oracle.guildedthorn.arpa/";
        caCertificate = ../../certs/ThornCloud_CA.crt;
        resolve = "oracle.guildedthorn.arpa:443:172.16.25.60";
      }
    ];
    readyLines = [
      "Oracle: https://oracle.guildedthorn.arpa/"
      "Read the generated administrator credential with:"
      "  ssh root@172.16.25.60 oracle-admin-password"
      "Add a pfSense host override for oracle.guildedthorn.arpa -> 172.16.25.60."
    ];
  };
}
